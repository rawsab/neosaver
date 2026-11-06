import AppKit
import Accelerate

// Samples the current frame and blurs only the region underneath each glass card.
final class GlassSurface {
    func drawBackground(blurred: CGImage?, in rect: CGRect, context: CGContext, opacity: CGFloat = 0.5) {
        context.saveGState()
        // Apply opacity once to the combined backdrop + tint. An opaque blurred crop
        // would otherwise erase the original dither even when the tint is translucent.
        context.setAlpha(opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        if let blurred {
            context.interpolationQuality = .high
            context.draw(blurred, in: rect)
        }
        context.setFillColor(NSColor(white: 0.30, alpha: 0.5).cgColor)
        context.fill(rect)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    func backdrop(from image: CGImage, viewport: NSRect, cardRect: NSRect, blurRadius: CGFloat) -> CGImage? {
        let sx = CGFloat(image.width) / viewport.width
        let sy = CGFloat(image.height) / viewport.height
        let sample = CGRect(x: (cardRect.minX - viewport.minX) * sx,
                            y: (cardRect.minY - viewport.minY) * sy,
                            width: cardRect.width * sx, height: cardRect.height * sy)
        let radius = max(1, Int((blurRadius * sx).rounded()))
        let padding = CGFloat(radius * 3 + 3)
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // CGImage crops use a top-left origin; the scene's CGContext image coordinates do not.
        let crop = CGRect(x: sample.minX, y: CGFloat(image.height) - sample.maxY,
                          width: sample.width, height: sample.height)
        let expanded = crop.insetBy(dx: -padding, dy: -padding).integral.intersection(extent)
        guard let region = image.cropping(to: expanded) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32,
            colorSpace: Unmanaged.passUnretained(colorSpace),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            version: 0, decode: nil, renderingIntent: .defaultIntent)
        var source = vImage_Buffer()
        guard vImageBuffer_InitWithCGImage(&source, &format, nil, region, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }
        guard let temporary = malloc(source.rowBytes * Int(source.height)) else { free(source.data); return nil }
        var target = vImage_Buffer(data: temporary, height: source.height, width: source.width, rowBytes: source.rowBytes)
        defer { free(source.data); free(target.data) }
        let kernel = UInt32(radius * 2 + 1)
        // Three box passes approximate a Gaussian, without a GPU/readback dependency in saver hosts.
        for _ in 0..<3 {
            guard vImageBoxConvolve_ARGB8888(&source, &target, nil, 0, 0, kernel, kernel, nil,
                vImage_Flags(kvImageEdgeExtend)) == kvImageNoError else { return nil }
            swap(&source, &target)
        }
        guard let blurred = vImageCreateCGImageFromBuffer(&source, &format, nil, nil,
            vImage_Flags(kvImageNoFlags), nil)?.takeRetainedValue() else { return nil }
        let outputRect = crop.offsetBy(dx: -expanded.minX, dy: -expanded.minY)
        return blurred.cropping(to: outputRect)
    }
}
