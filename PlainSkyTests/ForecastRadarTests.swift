import CoreGraphics
import MapKit
import XCTest
@testable import PlainSky

final class ForecastRadarTests: XCTestCase {
    private let runStart = ISO8601DateFormatter().date(from: "2026-09-22T21:00:00Z")!

    func testFramesStartAfterLatestScanAndStopAtHorizon() {
        let latestScan = runStart.addingTimeInterval(150 * 60)
        let horizon = latestScan.addingTimeInterval(2 * 60 * 60)

        let frames = HRRRForecastRadarProvider.frames(runStart: runStart, after: latestScan, until: horizon)

        XCTAssertEqual(frames.count, 8)
        XCTAssertTrue(frames.allSatisfy { $0.kind == .forecast })
        XCTAssertEqual(frames.first?.timestamp, runStart.addingTimeInterval(165 * 60))
        XCTAssertEqual(frames.last?.timestamp, runStart.addingTimeInterval(270 * 60))
        XCTAssertEqual(frames.first?.layerName, "hrrr::REFD-F0165-202609222100")
    }

    func testFramesNeverExceedModelLength() {
        let frames = HRRRForecastRadarProvider.frames(
            runStart: runStart,
            after: runStart,
            until: runStart.addingTimeInterval(48 * 60 * 60)
        )

        XCTAssertEqual(
            frames.last?.timestamp,
            runStart.addingTimeInterval(Double(HRRRForecastRadarProvider.maximumForecastMinute) * 60)
        )
    }

    func testTileURLUsesPinnedLayerAndXYZPath() {
        let frame = HRRRForecastRadarProvider.frames(
            runStart: runStart,
            after: runStart,
            until: runStart.addingTimeInterval(15 * 60)
        )[0]

        let url = ForecastRadarTileOverlay(frame: frame).url(
            forTilePath: .init(x: 33, y: 48, z: 7, contentScaleFactor: 3)
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/hrrr::REFD-F0015-202609222100/7/33/48.png"
        )
    }

    func testRecolorMapsKnownReflectivityAndDropsUnknownColors() throws {
        let image = try RadarTestImages.make(width: 2, height: 1) { x, _ in
            x == 0 ? (13, 158, 17, 255) : (1, 2, 3, 255)
        }

        let recolored = try XCTUnwrap(ForecastRadarTileOverlay.recolor(image))
        let pixels = try RadarTestImages.rgbaPixels(of: recolored)

        let mapped = try XCTUnwrap(ForecastRadarPalette.iemToNOAA[0x0D9E11])
        XCTAssertEqual(pixels[0], UInt8((mapped >> 16) & 0xFF))
        XCTAssertEqual(pixels[1], UInt8((mapped >> 8) & 0xFF))
        XCTAssertEqual(pixels[2], UInt8(mapped & 0xFF))
        XCTAssertEqual(pixels[3], 255)
        XCTAssertEqual(pixels[7], 0)
    }

    func testSourcePlanUsesTheTileItselfWhereCellsAreSubPixel() {
        let path = MKTileOverlayPath(x: 7, y: 12, z: 5, contentScaleFactor: 2)

        let plan = ForecastRadarTileOverlay.sourcePlan(for: path, minimumZoom: 2)

        XCTAssertEqual(plan.zoom, 5)
        XCTAssertNil(plan.smoothing)
        XCTAssertEqual(plan.footprintPixels, 256)
        XCTAssertEqual(plan.region, CGRect(x: 7 * 256, y: 12 * 256, width: 256, height: 256))
        XCTAssertEqual(plan.sourceTiles.count, 1)
        XCTAssertEqual(plan.sourceTiles.first?.x, 7)
        XCTAssertEqual(plan.sourceTiles.first?.y, 12)
    }

    func testSourcePlanStitchesNeighborsAtTheSameZoom() throws {
        let path = MKTileOverlayPath(x: 62, y: 95, z: 8, contentScaleFactor: 2)

        let plan = ForecastRadarTileOverlay.sourcePlan(for: path, minimumZoom: 2)
        let smoothing = try XCTUnwrap(plan.smoothing)

        XCTAssertEqual(plan.zoom, 8)
        XCTAssertEqual(plan.footprintPixels, 256)
        XCTAssertEqual(plan.region.width, CGFloat(256 + 2 * smoothing.margin))
        XCTAssertEqual(plan.sourceTiles.count, 9)
        XCTAssertTrue(plan.sourceTiles.allSatisfy { $0.z == 8 && (61...63).contains($0.x) && (94...96).contains($0.y) })
    }

    func testSourcePlanUsesCoarserTilesWhenZoomedIn() throws {
        let path = MKTileOverlayPath(x: 1_000, y: 800, z: 11, contentScaleFactor: 2)

        let plan = ForecastRadarTileOverlay.sourcePlan(for: path, minimumZoom: 2)
        let smoothing = try XCTUnwrap(plan.smoothing)

        XCTAssertEqual(plan.zoom, 8)
        XCTAssertEqual(plan.footprintPixels, 32)
        XCTAssertEqual(plan.region.width, CGFloat(32 + 2 * smoothing.margin))
        XCTAssertEqual(plan.sourceTiles.count, 4)
        XCTAssertTrue(plan.sourceTiles.allSatisfy { $0.z == 8 })
        XCTAssertTrue(plan.sourceTiles.contains { $0.x == 125 && $0.y == 100 })
    }

    func testSourcePlanNeverGoesBelowMinimumZoom() {
        let path = MKTileOverlayPath(x: 3, y: 5, z: 9, contentScaleFactor: 2)

        let plan = ForecastRadarTileOverlay.sourcePlan(for: path, minimumZoom: 9)

        XCTAssertEqual(plan.zoom, 9)
        XCTAssertEqual(plan.footprintPixels, 256)
    }

    func testSmoothedTileStitchesNeighborsIntoFullSizeTile() throws {
        let path = MKTileOverlayPath(x: 62, y: 95, z: 8, contentScaleFactor: 2)
        let plan = ForecastRadarTileOverlay.sourcePlan(for: path, minimumZoom: 2)

        let green = try RadarTestImages.make(width: 256, height: 256) { _, _ in (0, 200, 0, 255) }
        let red = try RadarTestImages.make(width: 256, height: 256) { _, _ in (200, 0, 0, 255) }
        let sources = plan.sourceTiles.map { source in
            (path: source, image: source.x == 62 && source.y == 95 ? green : red)
        }

        let tile = try XCTUnwrap(ForecastRadarTileOverlay.smoothedTile(from: sources, plan: plan))
        let image = try XCTUnwrap(RadarTileSmoother.decode(tile))
        let pixels = try RadarTestImages.rgbaPixels(of: image)

        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 512)

        let center = RadarTestImages.pixel(pixels, x: 256, y: 256, width: 512)
        XCTAssertEqual(center.green, 200, accuracy: 2)
        XCTAssertEqual(center.red, 0, accuracy: 2)

        // Edges blend into the neighbors' data instead of fading into transparency.
        let edge = RadarTestImages.pixel(pixels, x: 0, y: 256, width: 512)
        XCTAssertEqual(edge.alpha, 255, accuracy: 1)
        XCTAssertGreaterThan(edge.red, 30)
        XCTAssertGreaterThan(edge.green, 30)
    }

    func testSmoothedTileToleratesMissingNeighbors() throws {
        let path = MKTileOverlayPath(x: 0, y: 0, z: 8, contentScaleFactor: 2)
        let plan = ForecastRadarTileOverlay.sourcePlan(for: path, minimumZoom: 2)
        let green = try RadarTestImages.make(width: 256, height: 256) { _, _ in (0, 200, 0, 255) }

        let tile = try XCTUnwrap(
            ForecastRadarTileOverlay.smoothedTile(
                from: [(path: MKTileOverlayPath(x: 0, y: 0, z: 8, contentScaleFactor: 1), image: green)],
                plan: plan
            )
        )
        let image = try XCTUnwrap(RadarTileSmoother.decode(tile))
        let pixels = try RadarTestImages.rgbaPixels(of: image)

        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(RadarTestImages.pixel(pixels, x: 256, y: 256, width: 512).green, 200, accuracy: 2)
    }
}
