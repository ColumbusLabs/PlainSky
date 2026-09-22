import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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
        let green: (UInt8, UInt8, UInt8) = (13, 158, 17)
        let unknown: (UInt8, UInt8, UInt8) = (1, 2, 3)
        let image = try makeImage(width: 2, height: 1, pixels: [green, unknown])

        let recolored = try XCTUnwrap(ForecastRadarTileOverlay.recolor(image))
        let pixels = try rgbaPixels(of: recolored)

        let mapped = try XCTUnwrap(ForecastRadarPalette.iemToNOAA[0x0D9E11])
        XCTAssertEqual(pixels[0], UInt8((mapped >> 16) & 0xFF))
        XCTAssertEqual(pixels[1], UInt8((mapped >> 8) & 0xFF))
        XCTAssertEqual(pixels[2], UInt8(mapped & 0xFF))
        XCTAssertEqual(pixels[3], 255)
        XCTAssertEqual(pixels[7], 0)
    }

    func testSmoothedTileDoublesResolution() throws {
        let image = try makeImage(
            width: 256,
            height: 256,
            pixels: Array(repeating: (13, 158, 17), count: 256 * 256)
        )
        let data = try XCTUnwrap(pngData(image))

        let smoothed = try XCTUnwrap(ForecastRadarTileOverlay.smoothedTile(from: data))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(smoothed as CFData, nil))
        let output = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        XCTAssertEqual(output.width, 512)
        XCTAssertEqual(output.height, 512)
    }

    private func makeImage(width: Int, height: Int, pixels: [(UInt8, UInt8, UInt8)]) throws -> CGImage {
        var bytes = [UInt8]()
        for (red, green, blue) in pixels {
            bytes += [red, green, blue, 255]
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

    private func rgbaPixels(of image: CGImage) throws -> [UInt8] {
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

    private func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
