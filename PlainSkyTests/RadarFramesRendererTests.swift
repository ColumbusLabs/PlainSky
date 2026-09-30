import MapKit
import XCTest
@testable import PlainSky

final class RadarFramesRendererTests: XCTestCase {
    private func frame(_ id: String, kind: RadarFrame.Kind = .observed) -> RadarFrame {
        RadarFrame(
            id: id,
            timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
            serviceURL: URL(string: "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows")!,
            layerName: "conus_bref_qcd",
            kind: kind
        )
    }

    func testZoomLevelMatchesTileOverlayZoomAndIsClamped() {
        // At zoom scale 2^-10 a 256-point tile spans 2^18 map points: level 10.
        XCTAssertEqual(RadarFramesRenderer.zoomLevel(for: pow(2, -10)), 10)
        XCTAssertEqual(RadarFramesRenderer.zoomLevel(for: pow(2, -9.6)), 10)
        XCTAssertEqual(RadarFramesRenderer.zoomLevel(for: pow(2, -10.4)), 10)
        XCTAssertEqual(RadarFramesRenderer.zoomLevel(for: 1), RadarFramesRenderer.maximumZoom)
        XCTAssertEqual(RadarFramesRenderer.zoomLevel(for: pow(2, -25)), RadarFramesRenderer.minimumZoom)
    }

    func testTileMapRectTilesTheWorld() {
        let world = MKMapSize.world.width
        let rect = RadarFramesRenderer.mapRect(for: MKTileOverlayPath(x: 3, y: 1, z: 2, contentScaleFactor: 1))

        XCTAssertEqual(rect.minX, world * 3 / 4, accuracy: 0.001)
        XCTAssertEqual(rect.minY, world / 4, accuracy: 0.001)
        XCTAssertEqual(rect.width, world / 4, accuracy: 0.001)
        XCTAssertEqual(rect.height, world / 4, accuracy: 0.001)
    }

    func testTilePathsCoverTheDrawnRectAndStayInsideTheWorld() {
        let world = MKMapSize.world.width
        let tile = world / 8

        let inside = RadarFramesRenderer.tilePaths(
            covering: MKMapRect(x: tile * 2.5, y: tile * 3.5, width: tile, height: tile),
            zoom: 3,
            contentScaleFactor: 3
        )
        XCTAssertEqual(inside.count, 4)
        XCTAssertTrue(inside.allSatisfy { (2...3).contains($0.x) && (3...4).contains($0.y) && $0.z == 3 })
        XCTAssertTrue(inside.allSatisfy { $0.contentScaleFactor == 3 })

        let aligned = RadarFramesRenderer.tilePaths(
            covering: MKMapRect(x: tile * 2, y: tile * 3, width: tile, height: tile),
            zoom: 3,
            contentScaleFactor: 1
        )
        XCTAssertEqual(aligned.count, 1)
        XCTAssertEqual(aligned.first?.x, 2)
        XCTAssertEqual(aligned.first?.y, 3)

        let edge = RadarFramesRenderer.tilePaths(
            covering: MKMapRect(x: -tile, y: world - tile / 2, width: tile * 2, height: tile * 2),
            zoom: 3,
            contentScaleFactor: 1
        )
        XCTAssertEqual(edge.count, 1)
        XCTAssertEqual(edge.first?.x, 0)
        XCTAssertEqual(edge.first?.y, 7)
    }

    func testLoadersAreSharedPerFrameAndReleasedWithTheLoop() {
        let renderer = RadarFramesRenderer(overlay: RadarFramesOverlay())
        let observed = frame("a")
        let forecast = frame("b", kind: .forecast)

        let first = renderer.loader(for: observed)
        XCTAssertTrue(first === renderer.loader(for: observed))
        XCTAssertTrue(first is RadarWMSTileOverlay)
        XCTAssertTrue(renderer.loader(for: forecast) is ForecastRadarTileOverlay)

        renderer.retainLoaders(for: [forecast])
        XCTAssertFalse(first === renderer.loader(for: observed))
    }

    func testDisplayTracksCurrentFrame() {
        let renderer = RadarFramesRenderer(overlay: RadarFramesOverlay())
        XCTAssertNil(renderer.displayedFrame)

        renderer.display(frame("a"))
        XCTAssertEqual(renderer.displayedFrame?.id, "a")

        renderer.display(frame("b"))
        XCTAssertEqual(renderer.displayedFrame?.id, "b")

        renderer.display(nil)
        XCTAssertNil(renderer.displayedFrame)
    }

    func testRendererCanAlwaysDrawSoMissingTilesRedrawWhenLoaded() {
        let renderer = RadarFramesRenderer(overlay: RadarFramesOverlay())
        XCTAssertTrue(renderer.canDraw(.world, zoomScale: 1))
    }
}
