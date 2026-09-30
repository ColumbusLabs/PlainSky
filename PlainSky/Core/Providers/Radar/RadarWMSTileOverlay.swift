import CoreImage
import Foundation
import MapKit

/// NOAA base reflectivity from the NCEP GeoServer. The server draws each ~1 km radar cell as
/// a hard-edged block, so every tile is fetched with a margin of surrounding data, blurred by
/// about half a cell, and scaled up smoothly on device before MapKit draws it.
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

    /// MRMS reflectivity is published on a 0.01° grid, about 1.1 km across.
    static let cellMeters: Double = 1_113

    /// The smallest tile footprint requested from the server; below this the bicubic upscale
    /// has too little to work with.
    private static let minimumWorkingPixels = 8

    init(frame: RadarFrame) {
        self.frame = frame
        super.init(urlTemplate: nil)

        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 2
        maximumZ = 14
        canReplaceMapContent = false
    }

    /// How a tile is fetched from the server and turned into the image MapKit draws.
    struct TileRequest: Equatable {
        /// Square pixel size of the image handed to MapKit.
        let outputPixels: Int
        /// Pixels the tile's own footprint spans in the server request. Smaller than
        /// `outputPixels` at high zoom, where fetching every screen pixel would only repeat the
        /// same radar cell hundreds of times.
        let workingPixels: Int
        let smoothing: RadarTileSmoother.Plan?

        /// Pixel size of the image requested from the server, including the margin.
        var requestedPixels: Int {
            workingPixels + 2 * (smoothing?.margin ?? 0)
        }
    }

    func tileRequest(for path: MKTileOverlayPath) -> TileRequest {
        let pixelScale = min(max(path.contentScaleFactor, 1), Self.maximumPixelScale)
        let outputPixels = Int(tileSize.width * pixelScale)
        let cellPixels = RadarTileSmoother.cellPixels(
            cellMeters: Self.cellMeters,
            zoom: path.z,
            pixelScale: Double(pixelScale)
        )

        guard RadarTileSmoother.plan(cellPixels: cellPixels) != nil else {
            return TileRequest(outputPixels: outputPixels, workingPixels: outputPixels, smoothing: nil)
        }

        let workingScale = min(1, RadarTileSmoother.targetCellPixels / cellPixels)
        let workingPixels = max(
            Self.minimumWorkingPixels,
            Int((Double(outputPixels) * workingScale).rounded())
        )
        let workingCellPixels = cellPixels * Double(workingPixels) / Double(outputPixels)

        return TileRequest(
            outputPixels: outputPixels,
            workingPixels: workingPixels,
            smoothing: RadarTileSmoother.plan(cellPixels: workingCellPixels)
        )
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        url(forTilePath: path, request: tileRequest(for: path))
    }

    private func url(forTilePath path: MKTileOverlayPath, request: TileRequest) -> URL {
        let mercatorExtent = 20_037_508.342_789_244
        let tileCount = pow(2.0, Double(path.z))
        let span = (mercatorExtent * 2) / tileCount
        // The margin extends the bounding box past the tile so the blur sees neighboring data.
        let padding = span * Double(request.smoothing?.margin ?? 0) / Double(request.workingPixels)

        let minX = -mercatorExtent + Double(path.x) * span - padding
        let maxX = minX + span + 2 * padding
        let maxY = mercatorExtent - Double(path.y) * span + padding
        let minY = maxY - span - 2 * padding

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
            URLQueryItem(name: "WIDTH", value: String(request.requestedPixels)),
            URLQueryItem(name: "HEIGHT", value: String(request.requestedPixels)),
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

    func cachedTile(at path: MKTileOverlayPath) -> Data? {
        Self.tileCache.object(forKey: url(forTilePath: path) as NSURL) as Data?
    }

    /// Same as `loadTile` but without recording the zoom, for prefetch requests.
    func prefetchTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        let tileRequest = tileRequest(for: path)
        let url = url(forTilePath: path, request: tileRequest)

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
                  let tile = Self.smoothedTile(from: data, request: tileRequest) else {
                result(nil, error ?? ProviderError.invalidResponse)
                return
            }

            Self.tileCache.setObject(tile as NSData, forKey: url as NSURL, cost: tile.count)
            result(tile, nil)
        }
        .resume()
    }

    /// The image MapKit should draw for a server response, or the response itself when the
    /// tile needs no smoothing.
    static func smoothedTile(from data: Data, request: TileRequest) -> Data? {
        guard let smoothing = request.smoothing else { return data }

        guard let image = RadarTileSmoother.decode(data),
              let smoothed = RadarTileSmoother.smooth(
                  CIImage(cgImage: image),
                  margin: smoothing.margin,
                  sigma: smoothing.sigma,
                  outputPixels: request.outputPixels
              ) else {
            return nil
        }

        return RadarTileSmoother.pngData(smoothed)
    }
}
