import AppKit
import CoreText

// Uses the locally installed face; the font file is not copied into either bundle.
enum ClockTypography {
    private static let descriptor: NSFontDescriptor? = {
        let name = "Geist-Regular"
        if NSFont(name: name, size: 12) == nil {
            // Some screensaver/command-line hosts need process-local font registration.
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Fonts/Geist-VariableFont_wght.ttf")
            if FileManager.default.fileExists(atPath: url.path) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        return NSFont(name: name, size: 12)?.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
            ]]
        ])
    }()

    static func digits(ofSize size: CGFloat) -> NSFont {
        if let descriptor, let font = NSFont(descriptor: descriptor, size: size) { return font }
        return .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    private static var outlineCache: [String: CGPath] = [:]

    private static func outline(_ value: String, size: CGFloat) -> CGPath {
        let key = "\(size):\(value)"
        if let cached = outlineCache[key] { return cached }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
            .font: digits(ofSize: size), .kern: -5 * size / 94
        ]))
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for index in 0..<count {
                if let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) {
                    path.addPath(glyph, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
                }
            }
        }
        let result = path.copy()!
        outlineCache[key] = result
        return result
    }

    static func drawDigits(_ value: String, in rect: NSRect, size: CGFloat, verticalNudge: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let path = outline(value, size: size)
        let ink = path.boundingBoxOfPath
        guard !ink.isEmpty else { return }
        context.saveGState()
        // Core Text outlines use a bottom-up baseline; the scene uses flipped coordinates.
        context.translateBy(x: rect.midX - ink.midX, y: rect.midY + ink.midY + verticalNudge)
        context.scaleBy(x: 1, y: -1)
        context.addPath(path)
        context.clip()
        context.setFillColor(NSColor(white: 0.98, alpha: 0.75).cgColor)
        context.fill(ink)

        context.restoreGState()
    }

}
