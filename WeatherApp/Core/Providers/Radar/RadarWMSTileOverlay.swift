import Foundation
import MapKit

final class RadarWMSTileOverlay: MKTileOverlay {
    let frame: RadarFrame

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
            URLQueryItem(name: "WIDTH", value: String(Int(tileSize.width))),
            URLQueryItem(name: "HEIGHT", value: String(Int(tileSize.height))),
            URLQueryItem(name: "TILED", value: "TRUE"),
            URLQueryItem(name: "TIME", value: formatter.string(from: frame.timestamp))
        ]

        return components.url ?? frame.serviceURL
    }
}
