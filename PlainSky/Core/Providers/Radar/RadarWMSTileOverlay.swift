import Foundation
import MapKit

final class RadarWMSTileOverlay: MKTileOverlay {
    let frame: RadarFrame
    let zoomRecorder = RequestedZoomRecorder()

    /// Frames are fixed timestamps, so a tile never changes once fetched; NOAA sends no
    /// cache headers, so tiles are kept here to make looping playback instant.
    private static let tileCache: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private static let maximumPixelScale: CGFloat = 2

    init(frame: RadarFrame) {
        self.frame = frame
        super.init(urlTemplate: nil)

        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 2
        maximumZ = 14
        canReplaceMapContent = false
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let mercatorExtent = 20_037_508.342_789_244
        let tileCount = pow(2.0, Double(path.z))
        let span = (mercatorExtent * 2) / tileCount

        let minX = -mercatorExtent + Double(path.x) * span
        let maxX = minX + span
        let maxY = mercatorExtent - Double(path.y) * span
        let minY = maxY - span

        let pixelScale = min(max(path.contentScaleFactor, 1), Self.maximumPixelScale)
        let pixelWidth = Int(tileSize.width * pixelScale)
        let pixelHeight = Int(tileSize.height * pixelScale)

        var components = URLComponents(
            url: frame.serviceURL,
            resolvingAgainstBaseURL: false
        )!

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        components.queryItems = [
            URLQueryItem(name: "SERVICE", value: "WMS"),
            URLQueryItem(name: "VERSION", value: "1.1.1"),
            URLQueryItem(name: "REQUEST", value: "GetMap"),
            URLQueryItem(name: "LAYERS", value: frame.layerName),
            URLQueryItem(name: "STYLES", value: ""),
            URLQueryItem(name: "FORMAT", value: "image/png"),
            URLQueryItem(name: "TRANSPARENT", value: "TRUE"),
            URLQueryItem(name: "SRS", value: "EPSG:3857"),
            URLQueryItem(
                name: "BBOX",
                value: "\(minX),\(minY),\(maxX),\(maxY)"
            ),
            URLQueryItem(name: "WIDTH", value: String(pixelWidth)),
            URLQueryItem(name: "HEIGHT", value: String(pixelHeight)),
            URLQueryItem(name: "INTERPOLATIONS", value: "bilinear"),
            URLQueryItem(name: "TILED", value: "TRUE"),
            URLQueryItem(name: "TIME", value: formatter.string(from: frame.timestamp))
        ]

        return components.url ?? frame.serviceURL
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
                  (200..<300).contains(response.statusCode) else {
                result(nil, error ?? ProviderError.invalidResponse)
                return
            }

            Self.tileCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
            result(data, nil)
        }
        .resume()
    }
}
