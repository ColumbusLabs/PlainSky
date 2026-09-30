import CoreGraphics
import Foundation
import MapKit

/// One overlay for the whole radar loop. Frames change by redrawing the overlay in place, so
/// playback never stacks two frames (which briefly darkened every echo and read as flashing)
/// and never removes a frame before the next one is on screen.
final class RadarFramesOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D {
        MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate
    }

    var boundingMapRect: MKMapRect { .world }
}

/// Draws the current frame's tiles from the tile loaders' caches. A tile that is not cached
/// yet is fetched, the area is redrawn when it arrives, and meanwhile the previous frame's
/// tile keeps covering it so nothing goes blank mid-loop.
final class RadarFramesRenderer: MKOverlayRenderer {
    static let minimumZoom = 2
    static let maximumZoom = 14
    private static let tilePoints = 256.0

    private let lock = NSLock()
    private var currentFrame: RadarFrame?
    private var previousFrame: RadarFrame?
    private var loaders: [String: any RadarTileOverlay] = [:]
    private var pendingLoads: Set<String> = []
    private var lastDrawnZoom: Int?

    /// Decoded tiles, keyed by frame and tile path; the loaders keep the encoded data.
    private let imageCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// The zoom level MapKit last drew at, so prefetching can target it exactly.
    var lastRequestedZoom: Int? {
        lock.withLock { lastDrawnZoom }
    }

    var displayedFrame: RadarFrame? {
        lock.withLock { currentFrame }
    }

    /// The tile loader for a frame, shared between drawing and prefetching so both fill and
    /// read the same cache.
    func loader(for frame: RadarFrame) -> any RadarTileOverlay {
        lock.withLock {
            if let loader = loaders[frame.id] { return loader }
            let loader = RadarTileOverlayFactory.overlay(for: frame)
            loaders[frame.id] = loader
            return loader
        }
    }

    /// Drops loaders for frames that are no longer part of the loop.
    func retainLoaders(for frames: [RadarFrame]) {
        let ids = Set(frames.map(\.id))
        lock.withLock { loaders = loaders.filter { ids.contains($0.key) } }
    }

    /// Makes `frame` the one drawn from the next redraw on. Callers follow this with
    /// `setNeedsDisplay()` on the main thread.
    func display(_ frame: RadarFrame?) {
        lock.withLock {
            guard frame != currentFrame else { return }
            previousFrame = currentFrame
            currentFrame = frame
        }
    }

    // MARK: Tile geometry

    /// The tile zoom level whose 256-point tiles best match MapKit's current scale.
    static func zoomLevel(for zoomScale: MKZoomScale) -> Int {
        let worldTiles = MKMapSize.world.width / tilePoints
        let exact = log2(worldTiles * Double(zoomScale))
        return min(max(Int(exact.rounded()), minimumZoom), maximumZoom)
    }

    static func mapRect(for path: MKTileOverlayPath) -> MKMapRect {
        let tileSize = MKMapSize.world.width / Double(1 << path.z)
        return MKMapRect(
            x: Double(path.x) * tileSize,
            y: Double(path.y) * tileSize,
            width: tileSize,
            height: tileSize
        )
    }

    static func tilePaths(
        covering mapRect: MKMapRect,
        zoom: Int,
        contentScaleFactor: CGFloat
    ) -> [MKTileOverlayPath] {
        let tileCount = 1 << zoom
        let tileSize = MKMapSize.world.width / Double(tileCount)
        let minX = max(0, Int(floor(mapRect.minX / tileSize)))
        let maxX = min(tileCount - 1, Int(ceil(mapRect.maxX / tileSize)) - 1)
        let minY = max(0, Int(floor(mapRect.minY / tileSize)))
        let maxY = min(tileCount - 1, Int(ceil(mapRect.maxY / tileSize)) - 1)
        guard minX <= maxX, minY <= maxY else { return [] }

        var paths: [MKTileOverlayPath] = []
        for y in minY...maxY {
            for x in minX...maxX {
                paths.append(MKTileOverlayPath(x: x, y: y, z: zoom, contentScaleFactor: contentScaleFactor))
            }
        }
        return paths
    }

    // MARK: Drawing

    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        true
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let zoom = Self.zoomLevel(for: zoomScale)
        let (frame, fallback): (RadarFrame?, RadarFrame?) = lock.withLock {
            lastDrawnZoom = zoom
            return (currentFrame, previousFrame)
        }
        guard let frame else { return }

        for path in Self.tilePaths(covering: mapRect, zoom: zoom, contentScaleFactor: contentScaleFactor) {
            let tileRect = Self.mapRect(for: path)

            if let image = image(for: frame, at: path) {
                draw(image, in: tileRect, context: context)
                continue
            }

            load(frame, at: path, thenRedrawing: tileRect)

            if let fallback, let image = image(for: fallback, at: path) {
                draw(image, in: tileRect, context: context)
            }
        }
    }

    private func draw(_ image: CGImage, in mapRect: MKMapRect, context: CGContext) {
        let target = rect(for: mapRect)

        // The renderer's context runs top-down like the map; Core Graphics draws images
        // bottom-up, so flip within the tile's rectangle.
        context.saveGState()
        context.translateBy(x: target.minX, y: target.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        context.restoreGState()
    }

    private static func cacheKey(for frame: RadarFrame, at path: MKTileOverlayPath) -> String {
        "\(frame.id)|\(path.z)/\(path.x)/\(path.y)"
    }

    private func image(for frame: RadarFrame, at path: MKTileOverlayPath) -> CGImage? {
        let key = Self.cacheKey(for: frame, at: path) as NSString
        if let image = imageCache.object(forKey: key) {
            return image
        }

        guard let data = loader(for: frame).cachedTile(at: path),
              let image = RadarTileSmoother.decode(data) else {
            return nil
        }

        imageCache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    private func load(_ frame: RadarFrame, at path: MKTileOverlayPath, thenRedrawing mapRect: MKMapRect) {
        let key = Self.cacheKey(for: frame, at: path)
        let alreadyLoading = lock.withLock { !pendingLoads.insert(key).inserted }
        guard !alreadyLoading else { return }

        loader(for: frame).prefetchTile(at: path) { [weak self] data, _ in
            guard let self else { return }
            self.lock.withLock { _ = self.pendingLoads.remove(key) }
            guard data != nil else { return }

            DispatchQueue.main.async {
                self.setNeedsDisplay(mapRect)
            }
        }
    }
}
