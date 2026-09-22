import CoreImage
import Foundation
import ImageIO
import MapKit
import UniformTypeIdentifiers

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
/// published as 256 px nearest-neighbor tiles, so each one is recolored to NOAA's scale,
/// upscaled, and softened on device.
final class ForecastRadarTileOverlay: MKTileOverlay, RadarTileOverlay {
    let frame: RadarFrame
    let zoomRecorder = RequestedZoomRecorder()

    private static let tileCache: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static let upscale: CGFloat = 2
    private static let blurRadius: Double = 2.2

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

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "PlainSky/0.1 (https://github.com/ColumbusLabs/PlainSky)",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.weather.dataTask(with: request) { data, response, error in
            guard let data,
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let processed = Self.smoothedTile(from: data) else {
                result(nil, error ?? ProviderError.invalidResponse)
                return
            }

            Self.tileCache.setObject(processed as NSData, forKey: url as NSURL, cost: processed.count)
            result(processed, nil)
        }
        .resume()
    }

    static func smoothedTile(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let recolored = recolor(image) else {
            return nil
        }

        let extent = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width) * upscale,
            height: CGFloat(image.height) * upscale
        )

        let smoothed = CIImage(cgImage: recolored)
            .samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: upscale, y: upscale))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: blurRadius)
            .cropped(to: extent)

        guard let output = ciContext.createCGImage(smoothed, from: extent) else { return nil }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return encoded as Data
    }

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
