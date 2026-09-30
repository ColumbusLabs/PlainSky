import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns blocky nearest-neighbor radar imagery into the continuous surface familiar from
/// broadcast radar. Source pixels are blurred by about half a radar cell so neighboring
/// cells blend into each other, then scaled to the output size with bicubic interpolation so
/// even a heavily zoomed-in cell has no hard edges.
///
/// Callers fetch a margin of extra pixels around each tile so the blur near a tile's edge
/// uses the neighboring tile's real data; blurring a tile on its own would leave visible
/// seams between tiles.
enum RadarTileSmoother {
    /// Radar cells that cover fewer pixels than this are already too small to look blocky.
    static let minimumSmoothedCellPixels: Double = 1.5

    /// Sources that can be fetched at any resolution are resampled so a radar cell spans about
    /// this many pixels before blurring, which keeps blur cost and request size bounded at
    /// zoom levels where one cell can span hundreds of screen pixels.
    static let targetCellPixels: Double = 6

    /// Ground resolution of a Web Mercator tile pixel at the equator at zoom 0, in meters.
    static let metersPerPixelAtZoomZero = 156_543.033_928_04

    /// How many tile pixels one radar cell covers at a zoom level. Uses the east–west size,
    /// which for a lat/lon grid drawn on a Mercator map does not vary with latitude.
    static func cellPixels(cellMeters: Double, zoom: Int, pixelScale: Double) -> Double {
        cellMeters * pow(2, Double(zoom)) * pixelScale / metersPerPixelAtZoomZero
    }

    struct Plan: Equatable {
        /// Gaussian sigma applied to the source pixels.
        let sigma: Double
        /// Source pixels needed on each side of the tile so the blur has real neighbors.
        let margin: Int
    }

    /// The blur needed to blend cells of the given size, or `nil` when cells are already too
    /// small to look blocky.
    static func plan(cellPixels: Double) -> Plan? {
        guard cellPixels >= minimumSmoothedCellPixels else { return nil }

        let sigma = 0.5 * cellPixels
        return Plan(sigma: sigma, margin: max(8, Int((3.5 * sigma).rounded(.up))))
    }

    /// Blends in sRGB rather than Core Image's default linear light, so the midpoint between
    /// two legend colors is the color a viewer expects rather than a lighter one.
    private static let ciContext = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    /// Blurs `source`, whose extent must be square with the tile in the middle and `margin`
    /// extra pixels on every side, then scales the tile to `outputPixels` square.
    static func smooth(
        _ source: CIImage,
        margin: Int,
        sigma: Double,
        outputPixels: Int
    ) -> CGImage? {
        let extent = source.extent
        let innerSize = extent.width - CGFloat(margin * 2)
        guard innerSize > 0, outputPixels > 0 else { return nil }

        var image = source
        if sigma > 0 {
            image = image
                .clampedToExtent()
                .applyingGaussianBlur(sigma: sigma)
                .cropped(to: extent)
        }

        image = image.transformed(
            by: CGAffineTransform(
                translationX: -extent.minX - CGFloat(margin),
                y: -extent.minY - CGFloat(margin)
            )
        )

        let scale = CGFloat(outputPixels) / innerSize
        if scale != 1 {
            // The margin is scaled too and cropped afterwards, so the tile's edge pixels are
            // interpolated from neighboring data rather than from transparent padding.
            let filter = CIFilter.bicubicScaleTransform()
            filter.inputImage = image
            filter.scale = Float(scale)
            filter.aspectRatio = 1
            // Mitchell–Netravali weights: smooth without the ringing sharper cubics add
            // along the edge of an echo.
            filter.parameterB = 1 / 3
            filter.parameterC = 1 / 3
            guard let scaled = filter.outputImage else { return nil }
            image = scaled
        }

        let output = CGRect(x: 0, y: 0, width: outputPixels, height: outputPixels)
        return ciContext.createCGImage(image.cropped(to: output), from: output)
    }

    static func pngData(_ image: CGImage) -> Data? {
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return encoded as Data
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
