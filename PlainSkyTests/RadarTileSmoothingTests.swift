import CoreImage
import ImageIO
import MapKit
import UniformTypeIdentifiers
import XCTest
@testable import PlainSky

final class RadarTileSmoothingTests: XCTestCase {
    private let frame = RadarFrame(
        id: "frame",
        timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
        serviceURL: URL(string: "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows")!,
        layerName: "conus_bref_qcd"
    )

    // MARK: Planning

    func testCellPixelsGrowWithZoomAndScale() {
        let zoom8 = RadarTileSmoother.cellPixels(cellMeters: 1_113, zoom: 8, pixelScale: 1)
        let zoom9 = RadarTileSmoother.cellPixels(cellMeters: 1_113, zoom: 9, pixelScale: 1)
        let retina = RadarTileSmoother.cellPixels(cellMeters: 1_113, zoom: 8, pixelScale: 2)

        XCTAssertEqual(zoom8, 1.82, accuracy: 0.01)
        XCTAssertEqual(zoom9, zoom8 * 2, accuracy: 0.001)
        XCTAssertEqual(retina, zoom8 * 2, accuracy: 0.001)
    }

    func testPlanSkipsSubPixelCellsAndBlursHalfACell() throws {
        XCTAssertNil(RadarTileSmoother.plan(cellPixels: 1))

        let plan = try XCTUnwrap(RadarTileSmoother.plan(cellPixels: 7))
        XCTAssertEqual(plan.sigma, 3.5)
        XCTAssertEqual(plan.margin, 13)
        XCTAssertGreaterThanOrEqual(Double(plan.margin), 3 * plan.sigma)
    }

    func testWMSRequestIsUnpaddedWhereCellsAreSubPixel() {
        let request = RadarWMSTileOverlay(frame: frame).tileRequest(
            for: MKTileOverlayPath(x: 1, y: 1, z: 2, contentScaleFactor: 2)
        )

        XCTAssertNil(request.smoothing)
        XCTAssertEqual(request.workingPixels, 512)
        XCTAssertEqual(request.requestedPixels, 512)
        XCTAssertEqual(request.outputPixels, 512)
    }

    func testWMSRequestFetchesCoarserPaddedImageWhenZoomedIn() throws {
        let overlay = RadarWMSTileOverlay(frame: frame)
        let path = MKTileOverlayPath(x: 270, y: 390, z: 10, contentScaleFactor: 2)
        let request = overlay.tileRequest(for: path)
        let smoothing = try XCTUnwrap(request.smoothing)

        XCTAssertEqual(request.outputPixels, 512)
        XCTAssertLessThan(request.workingPixels, 512)
        XCTAssertEqual(request.requestedPixels, request.workingPixels + 2 * smoothing.margin)
        XCTAssertEqual(smoothing.sigma, RadarTileSmoother.targetCellPixels / 2, accuracy: 0.1)

        let query = try queryItems(of: overlay.url(forTilePath: path))
        XCTAssertEqual(query["WIDTH"], String(request.requestedPixels))
        XCTAssertEqual(query["HEIGHT"], String(request.requestedPixels))

        let bbox = try XCTUnwrap(query["BBOX"]).split(separator: ",").compactMap { Double($0) }
        let tileSpan: Double = 2 * 20_037_508.342_789_244 / Double(1 << 10)
        let expectedSpan = tileSpan * Double(request.requestedPixels) / Double(request.workingPixels)
        XCTAssertEqual(bbox[2] - bbox[0], expectedSpan, accuracy: 0.01)
        XCTAssertEqual(bbox[3] - bbox[1], expectedSpan, accuracy: 0.01)
    }

    func testWMSRequestSizeStaysBoundedAtMaximumZoom() {
        let request = RadarWMSTileOverlay(frame: frame).tileRequest(
            for: MKTileOverlayPath(x: 4_000, y: 6_000, z: 14, contentScaleFactor: 3)
        )

        XCTAssertNotNil(request.smoothing)
        XCTAssertGreaterThanOrEqual(request.workingPixels, 8)
        XCTAssertLessThan(request.requestedPixels, 128)
        XCTAssertEqual(request.outputPixels, 512)
    }

    // MARK: Smoothing

    func testSmoothingCropsMarginAndScalesToOutputSize() throws {
        let margin = 8
        let inner = 64
        let source = try RadarTestImages.make(
            width: inner + 2 * margin,
            height: inner + 2 * margin
        ) { x, y in
            let isMargin = x < margin || y < margin || x >= inner + margin || y >= inner + margin
            return isMargin ? (255, 0, 0, 255) : (0, 200, 0, 255)
        }

        let output = try XCTUnwrap(
            RadarTileSmoother.smooth(
                CIImage(cgImage: source),
                margin: margin,
                sigma: 0,
                outputPixels: 512
            )
        )
        let pixels = try RadarTestImages.rgbaPixels(of: output)

        XCTAssertEqual(output.width, 512)
        XCTAssertEqual(output.height, 512)

        let center = RadarTestImages.pixel(pixels, x: 256, y: 256, width: 512)
        XCTAssertEqual(center.red, 0, accuracy: 2)
        XCTAssertEqual(center.green, 200, accuracy: 2)
        XCTAssertEqual(center.alpha, 255, accuracy: 1)

        // Four source pixels inside the edge is beyond the bicubic kernel's reach into the
        // margin, so the tile is still solid green there.
        let nearEdge = RadarTestImages.pixel(pixels, x: 32, y: 32, width: 512)
        XCTAssertEqual(nearEdge.red, 0, accuracy: 2)
        XCTAssertEqual(nearEdge.green, 200, accuracy: 2)

        // The very corner is interpolated from real margin data, not transparent padding.
        let corner = RadarTestImages.pixel(pixels, x: 0, y: 0, width: 512)
        XCTAssertEqual(corner.alpha, 255, accuracy: 1)
        XCTAssertGreaterThan(corner.green, 50)
    }

    func testBlurBlendsAcrossACellBoundary() throws {
        let size = 64
        let source = try RadarTestImages.make(width: size, height: size) { x, _ in
            x < size / 2 ? (0, 200, 0, 255) : (200, 0, 0, 255)
        }

        let output = try XCTUnwrap(
            RadarTileSmoother.smooth(CIImage(cgImage: source), margin: 0, sigma: 3, outputPixels: size)
        )
        let pixels = try RadarTestImages.rgbaPixels(of: output)

        let left = RadarTestImages.pixel(pixels, x: 8, y: 32, width: size)
        let boundary = RadarTestImages.pixel(pixels, x: 32, y: 32, width: size)
        let right = RadarTestImages.pixel(pixels, x: 56, y: 32, width: size)

        XCTAssertEqual(left.green, 200, accuracy: 3)
        XCTAssertEqual(right.red, 200, accuracy: 3)
        XCTAssertEqual(boundary.green, 100, accuracy: 25)
        XCTAssertEqual(boundary.red, 100, accuracy: 25)
    }

    func testWMSSmoothedTileReturnsResponseUnchangedWithoutSmoothing() {
        let data = Data([1, 2, 3])
        let request = RadarWMSTileOverlay.TileRequest(outputPixels: 512, workingPixels: 512, smoothing: nil)

        XCTAssertEqual(RadarWMSTileOverlay.smoothedTile(from: data, request: request), data)
    }

    func testWMSSmoothedTileProducesFullSizePNG() throws {
        let request = RadarWMSTileOverlay.TileRequest(
            outputPixels: 512,
            workingPixels: 64,
            smoothing: RadarTileSmoother.Plan(sigma: 3, margin: 11)
        )
        let source = try RadarTestImages.make(width: 86, height: 86) { _, _ in (0, 200, 0, 255) }
        let data = try XCTUnwrap(RadarTileSmoother.pngData(source))

        let tile = try XCTUnwrap(RadarWMSTileOverlay.smoothedTile(from: data, request: request))
        let image = try XCTUnwrap(RadarTileSmoother.decode(tile))

        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 512)
    }

    private func queryItems(of url: URL) throws -> [String: String] {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
    }
}

enum RadarTestImages {
    typealias RGBA = (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)

    static func make(width: Int, height: Int, pixel: (Int, Int) -> RGBA) throws -> CGImage {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = pixel(x, y)
                bytes += [value.red, value.green, value.blue, value.alpha]
            }
        }

        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
    }

    static func rgbaPixels(of image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    /// The pixel at a top-down coordinate, un-premultiplied.
    static func pixel(_ pixels: [UInt8], x: Int, y: Int, width: Int) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let offset = (y * width + x) * 4
        let alpha = Double(pixels[offset + 3])
        guard alpha > 0 else { return (0, 0, 0, 0) }
        return (
            Double(pixels[offset]) * 255 / alpha,
            Double(pixels[offset + 1]) * 255 / alpha,
            Double(pixels[offset + 2]) * 255 / alpha,
            alpha
        )
    }
}
