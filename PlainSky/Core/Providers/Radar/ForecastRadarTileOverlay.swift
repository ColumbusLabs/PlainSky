import CoreImage
import Foundation
import ImageIO
import MapKit

protocol RadarTileOverlay: MKTileOverlay {
    var frame: RadarFrame { get }
    var zoomRecorder: RequestedZoomRecorder { get }

    func prefetchTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void)
}

/// Records the zoom level MapKit actually requests, so prefetching can target it exactly.
final class RequestedZoomRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var zoom: Int?

    var lastRequestedZoom: Int? {
        lock.withLock { zoom }
    }

    func record(_ path: MKTileOverlayPath) {
        lock.withLock { zoom = path.z }
    }
}

extension RadarWMSTileOverlay: RadarTileOverlay {}

enum RadarTileOverlayFactory {
    static func overlay(for frame: RadarFrame) -> any RadarTileOverlay {
        switch frame.kind {
        case .observed: RadarWMSTileOverlay(frame: frame)
        case .forecast: ForecastRadarTileOverlay(frame: frame)
        }
    }
}

/// HRRR simulated reflectivity tiles from the Iowa Environmental Mesonet. They are only
/// published as 256 px nearest-neighbor tiles, so each one is recolored to NOAA's scale and
/// smoothed on device.
///
/// The server cannot pad a tile, so the smoothing source is stitched from the tiles around
/// it. At high zoom the source comes from a coarser zoom level, where each ~3 km model cell
/// is only a few pixels wide: that covers the tile and its margin with at most a few source
/// tiles and keeps the blur small, and the bicubic upscale afterwards is what makes the cells
/// blend smoothly instead of showing as blocks.
final class ForecastRadarTileOverlay: MKTileOverlay, RadarTileOverlay {
    let frame: RadarFrame
    let zoomRecorder = RequestedZoomRecorder()

    private static let tileCache: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    private static let sourceLoader = ForecastSourceTileLoader()

    /// HRRR runs on a 3 km grid.
    static let cellMeters: Double = 3_000
    /// Tiles are sourced from the coarsest zoom level where a cell still spans at least this
    /// many pixels: coarser source tiles cover more output tiles each, so far fewer are
    /// fetched, and the bicubic upscale makes the result just as smooth.
    static let minimumSourceCellPixels: Double = 3
    static let sourceTilePixels = 256
    static let outputPixels = 512

    init(frame: RadarFrame) {
        self.frame = frame
        super.init(urlTemplate: nil)

        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 2
        maximumZ = 14
        canReplaceMapContent = false
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let base = frame.serviceURL.absoluteString
        return URL(string: "\(base)\(frame.layerName)/\(path.z)/\(path.x)/\(path.y).png")
            ?? frame.serviceURL
    }

    // MARK: Source planning

    /// Where a tile's pixels come from: a square region of source pixels at `zoom`, covering
    /// the tile's footprint plus the smoothing margin.
    struct SourcePlan: Equatable {
        let zoom: Int
        /// Source pixels the tile itself spans at `zoom`.
        let footprintPixels: Int
        /// Region of the source zoom level's pixel grid to stitch, in top-down coordinates.
        let region: CGRect
        let smoothing: RadarTileSmoother.Plan?

        /// Source tiles intersecting the region; those outside the world are simply absent.
        var sourceTiles: [MKTileOverlayPath] {
            let tileCount = 1 << zoom
            let size = CGFloat(ForecastRadarTileOverlay.sourceTilePixels)
            let minX = max(0, Int(floor(region.minX / size)))
            let maxX = min(tileCount - 1, Int(ceil(region.maxX / size)) - 1)
            let minY = max(0, Int(floor(region.minY / size)))
            let maxY = min(tileCount - 1, Int(ceil(region.maxY / size)) - 1)
            guard minX <= maxX, minY <= maxY else { return [] }

            var paths: [MKTileOverlayPath] = []
            for y in minY...maxY {
                for x in minX...maxX {
                    paths.append(MKTileOverlayPath(x: x, y: y, z: zoom, contentScaleFactor: 1))
                }
            }
            return paths
        }
    }

    static func sourcePlan(for path: MKTileOverlayPath, minimumZoom: Int) -> SourcePlan {
        func cellPixels(at zoom: Int) -> Double {
            RadarTileSmoother.cellPixels(cellMeters: cellMeters, zoom: zoom, pixelScale: 1)
        }

        guard RadarTileSmoother.plan(cellPixels: cellPixels(at: path.z)) != nil else {
            return SourcePlan(
                zoom: path.z,
                footprintPixels: sourceTilePixels,
                region: CGRect(
                    x: path.x * sourceTilePixels,
                    y: path.y * sourceTilePixels,
                    width: sourceTilePixels,
                    height: sourceTilePixels
                ),
                smoothing: nil
            )
        }

        var zoom = path.z
        while zoom > minimumZoom, cellPixels(at: zoom - 1) >= minimumSourceCellPixels {
            zoom -= 1
        }

        let levelsUp = path.z - zoom
        let footprintPixels = max(1, sourceTilePixels >> levelsUp)
        let smoothing = RadarTileSmoother.plan(cellPixels: cellPixels(at: zoom))
        let margin = smoothing?.margin ?? 0
        let footprint = CGRect(
            x: path.x * footprintPixels,
            y: path.y * footprintPixels,
            width: footprintPixels,
            height: footprintPixels
        )

        return SourcePlan(
            zoom: zoom,
            footprintPixels: footprintPixels,
            region: footprint.insetBy(dx: CGFloat(-margin), dy: CGFloat(-margin)),
            smoothing: smoothing
        )
    }

    // MARK: Loading

    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        prefetchTile(at: path, result: result)
        zoomRecorder.record(path)
    }

    /// Same as `loadTile` but without recording the zoom, for prefetch requests.
    func prefetchTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        let url = url(forTilePath: path)

        if let cached = Self.tileCache.object(forKey: url as NSURL) {
            result(cached as Data, nil)
            return
        }

        let plan = Self.sourcePlan(for: path, minimumZoom: minimumZ)
        let sourceURLs = plan.sourceTiles.map { ($0, self.url(forTilePath: $0)) }

        Task.detached(priority: .utility) {
            do {
                let sources = try await withThrowingTaskGroup(
                    of: (MKTileOverlayPath, CGImage?).self
                ) { group in
                    for (sourcePath, sourceURL) in sourceURLs {
                        group.addTask {
                            (sourcePath, try await Self.sourceLoader.image(for: sourceURL))
                        }
                    }

                    var images: [(path: MKTileOverlayPath, image: CGImage)] = []
                    for try await (sourcePath, image) in group {
                        if let image { images.append((path: sourcePath, image: image)) }
                    }
                    return images
                }

                guard let tile = Self.smoothedTile(from: sources, plan: plan) else {
                    throw ProviderError.invalidResponse
                }

                Self.tileCache.setObject(tile as NSData, forKey: url as NSURL, cost: tile.count)
                result(tile, nil)
            } catch {
                result(nil, error)
            }
        }
    }

    /// Stitches the recolored source tiles over the plan's region, then smooths the tile out
    /// of the middle of it.
    static func smoothedTile(
        from sources: [(path: MKTileOverlayPath, image: CGImage)],
        plan: SourcePlan
    ) -> Data? {
        let regionSize = plan.region.width
        let tileSize = CGFloat(sourceTilePixels)
        let regionExtent = CGRect(x: 0, y: 0, width: regionSize, height: regionSize)
        // Start transparent so tiles beyond the edge of the world simply stay clear.
        var stitched = CIImage(color: .clear).cropped(to: regionExtent)

        for (path, image) in sources {
            // Core Image's origin is at the bottom left, while tile rows count downward.
            let offsetX = CGFloat(path.x) * tileSize - plan.region.minX
            let offsetY = regionSize - (CGFloat(path.y) * tileSize - plan.region.minY) - tileSize
            stitched = CIImage(cgImage: image)
                .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
                .composited(over: stitched)
        }

        guard let smoothed = RadarTileSmoother.smooth(
            stitched.cropped(to: regionExtent),
            margin: plan.smoothing?.margin ?? 0,
            sigma: plan.smoothing?.sigma ?? 0,
            outputPixels: outputPixels
        ) else {
            return nil
        }

        return RadarTileSmoother.pngData(smoothed)
    }

    // MARK: Recoloring

    static func recolor(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let buffer = context.data else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixels = buffer.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        for offset in stride(from: 0, to: bytesPerRow * height, by: 4) {
            guard pixels[offset + 3] == 255 else {
                clear(pixels, at: offset)
                continue
            }

            let key = UInt32(pixels[offset]) << 16
                | UInt32(pixels[offset + 1]) << 8
                | UInt32(pixels[offset + 2])

            guard let mapped = ForecastRadarPalette.iemToNOAA[key] else {
                clear(pixels, at: offset)
                continue
            }

            pixels[offset] = UInt8((mapped >> 16) & 0xFF)
            pixels[offset + 1] = UInt8((mapped >> 8) & 0xFF)
            pixels[offset + 2] = UInt8(mapped & 0xFF)
        }

        return context.makeImage()
    }

    private static func clear(_ pixels: UnsafeMutablePointer<UInt8>, at offset: Int) {
        pixels[offset] = 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = 0
    }
}

/// Fetches and recolors source tiles once each, however many output tiles share them:
/// a coarser-zoom source tile feeds every finer tile inside it, and neighbors feed each
/// other's margins.
actor ForecastSourceTileLoader {
    private let cache: NSCache<NSURL, CGImage> = {
        let cache = NSCache<NSURL, CGImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    private var inFlight: [URL: Task<CGImage?, Error>] = [:]

    /// The recolored tile, or `nil` where the server has no tile.
    func image(for url: URL) async throws -> CGImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        if let task = inFlight[url] {
            return try await task.value
        }

        let task = Task<CGImage?, Error> {
            try await Self.fetch(url)
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }

        let image = try await task.value
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        }
        return image
    }

    private static func fetch(_ url: URL) async throws -> CGImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "PlainSky/0.1 (https://github.com/ColumbusLabs/PlainSky)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.weather.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }

        if response.statusCode == 404 {
            return nil
        }

        guard (200..<300).contains(response.statusCode),
              let image = RadarTileSmoother.decode(data),
              let recolored = ForecastRadarTileOverlay.recolor(image) else {
            throw ProviderError.invalidResponse
        }

        return recolored
    }
}
