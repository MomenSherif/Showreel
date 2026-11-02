import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Synchronization
import ShowreelKit

/// Draws the caption on screen (S-041, S-056): centered text in the caption
/// style's font, weight, and colors, with an optional box, outline, and
/// shadow or glow, and the spoken word standing out. Drawn with Core Text at
/// the output size, so it is sharp at 4K, and cached per caption and word,
/// since it changes only a few times a second. Core Image coordinates.
public enum CaptionPainter {
    private struct Key: Hashable {
        let id: UUID, text: String, word: Int?, style: CaptionStyle, canvas: CGSize, language: String
    }

    private struct Image: @unchecked Sendable {
        // @unchecked: CIImage is immutable and thread-safe.
        let image: CIImage
    }

    private static let cache = Mutex<[Key: Image]>([:])

    /// The caption at source time `t` placed on a canvas of `size`, or nil
    /// when none shows.
    static func image(for captions: CaptionTrack, style: CaptionStyle, at t: Double, canvas size: CGSize) -> CIImage? {
        guard style.isVisible, let caption = captions.caption(at: t), !caption.words.isEmpty else { return nil }
        let word = style.highlightsWord ? caption.wordIndex(at: t) : nil
        let key = Key(id: caption.id, text: caption.text, word: word, style: style, canvas: size, language: captions.language)
        if let cached = cache.withLock({ $0[key] }) { return cached.image }
        guard let picture = picture(caption.words.map(\.text), word: word, style: style, canvas: size,
                                    rightToLeft: caption.isRightToLeft(language: captions.language)) else { return nil }
        let image = placed(picture, style: style, canvas: size)
        cache.withLock { cache in
            if cache.count > 24 { cache.removeAll() }
            cache[key] = Image(image: image)
        }
        return image
    }

    /// A caption style's tile (S-056): "Say hello" with "hello" spoken, on the
    /// Graphite gradient, `size` in pixels. The text is drawn as on a canvas
    /// `scale` times the tile's size, so small tiles still show the style.
    public static func sample(_ style: CaptionStyle, size: CGSize, scale: CGFloat = 4) -> CGImage? {
        var look = style
        look.size = 1
        let canvas = CGSize(width: size.width * scale, height: size.height * scale)
        guard let text = picture(["Say", "hello"], word: 1, style: look, canvas: canvas, rightToLeft: false),
              let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: Renderer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let backdrop = GradientPreset.named("graphite")!
        let colors = [backdrop.from, backdrop.to].map { CGColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1) }
        if let gradient = CGGradient(colorsSpace: Renderer.sRGB, colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        }
        // Fit the line in the tile, at most at its canvas size.
        let fit = min(1, 0.9 * size.width / CGFloat(text.width), 0.8 * size.height / CGFloat(text.height))
        let w = CGFloat(text.width) * fit, h = CGFloat(text.height) * fit
        ctx.interpolationQuality = .high
        ctx.draw(text, in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        return ctx.makeImage()
    }

    /// Sizes are set for a 1080-pixel canvas and follow its shorter side, so
    /// a tall video has captions as big as a wide one.
    static func unit(_ canvas: CGSize) -> CGFloat { min(canvas.width, canvas.height) / 1080 }

    static func fontSize(_ style: CaptionStyle, canvas: CGSize) -> CGFloat {
        46 * unit(canvas) * CGFloat(min(max(style.size, CaptionStyle.sizeRange.lowerBound), CaptionStyle.sizeRange.upperBound))
    }

    /// `picture` at its spot on the canvas: centered, 6% in from the bottom
    /// or the top, or in the middle.
    private static func placed(_ picture: CGImage, style: CaptionStyle, canvas: CGSize) -> CIImage {
        let margin = 0.06 * canvas.height
        let height = CGFloat(picture.height)
        let x = ((canvas.width - CGFloat(picture.width)) / 2).rounded()
        let y = switch style.position {
        case .bottom: margin.rounded()
        case .middle: ((canvas.height - height) / 2).rounded()
        case .top: (canvas.height - margin - height).rounded()
        }
        return CIImage(cgImage: picture).transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    /// One caption line, `words` with word `word` spoken, drawn for a canvas of `canvas`.
    private static func picture(_ words: [String], word: Int?, style: CaptionStyle, canvas: CGSize, rightToLeft: Bool) -> CGImage? {
        let u = unit(canvas)
        let fontSize = fontSize(style, canvas: canvas)
        let font = font(style, size: fontSize)

        // The words as one string, remembering where each one is.
        var text = ""
        var ranges: [NSRange] = []
        for (i, w) in words.enumerated() {
            if i > 0 { text += " " }
            let start = (text as NSString).length
            let clean = w.trimmingCharacters(in: .whitespaces)
            text += style.allCaps ? clean.uppercased() : clean
            ranges.append(NSRange(location: start, length: (text as NSString).length - start))
        }
        let ink = cgColor(style.textColor)
        let accent = cgColor(style.highlightColor)
        let spoken = word.flatMap { ranges.indices.contains($0) ? $0 : nil }

        let string = NSMutableAttributedString(string: text)
        let all = NSRange(location: 0, length: string.length)
        // Arabic reads from the right even when a line starts with an English
        // word (S-054); English words inside it keep their own order.
        var alignment = CTTextAlignment.center
        var direction = rightToLeft ? CTWritingDirection.rightToLeft : .leftToRight
        let paragraph = withUnsafeBytes(of: &alignment) { a in
            withUnsafeBytes(of: &direction) { d in
                var settings = [
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: a.baseAddress!),
                    CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: MemoryLayout<CTWritingDirection>.size,
                                            value: d.baseAddress!),
                ]
                return CTParagraphStyleCreate(&settings, settings.count)
            }
        }
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        string.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: font, range: all)
        string.addAttribute(colorKey, value: ink, range: all)
        string.addAttribute(NSAttributedString.Key(kCTParagraphStyleAttributeName as String), value: paragraph, range: all)
        // An outline needs room: letters move apart as it grows, so it never
        // closes the gaps between them.
        let outline = min(max(style.outline, 0), 1)
        if outline > 0 {
            string.addAttribute(NSAttributedString.Key(kCTKernAttributeName as String), value: 0.06 * outline * fontSize, range: all)
        }
        if let spoken {
            switch style.highlight {
            case .none: break
            case .pill:
                let onPill = luminance(style.highlightColor) > 0.55 ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
                                                                     : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
                string.addAttribute(colorKey, value: onPill, range: ranges[spoken])
            case .word:
                string.addAttribute(colorKey, value: accent, range: ranges[spoken])
            case .karaoke:
                string.addAttribute(colorKey, value: accent, range: NSUnionRange(ranges[0], ranges[spoken]))
            }
        }

        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let maxWidth = canvas.width * 0.84
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil,
                                                               CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
        let textSize = CGSize(width: ceil(fit.width) + 2, height: ceil(fit.height))
        // Without a box, the margin holds the outline and the shadow or glow.
        let pad = style.showsBox
            ? CGSize(width: (0.5 * fontSize).rounded(), height: (0.26 * fontSize).rounded())
            : CGSize(width: (0.4 * fontSize).rounded(), height: (0.3 * fontSize).rounded())
        let box = CGSize(width: textSize.width + 2 * pad.width, height: textSize.height + 2 * pad.height)

        let width = Int(box.width.rounded(.up)), height = Int(box.height.rounded(.up))
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Renderer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if style.showsBox, style.boxOpacity > 0 {
            ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: 0.3 * fontSize, cornerHeight: 0.3 * fontSize, transform: nil)) // grid: ok video pixels, relative to the font
            ctx.setFillColor(cgColor(style.boxColor, alpha: min(max(style.boxOpacity, 0), 1)))
            ctx.fillPath()
        }
        let textRect = CGRect(x: pad.width, y: pad.height, width: textSize.width, height: textSize.height)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)

        // The pill behind the spoken word, on each line the word is on.
        if let spoken, style.highlight == .pill {
            let range = ranges[spoken]
            let lines = CTFrameGetLines(frame) as! [CTLine]
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(), &origins)
            for (line, origin) in zip(lines, origins) {
                guard let (x0, x1) = span(of: range, in: line) else { continue }
                var ascent: CGFloat = 0, descent: CGFloat = 0
                CTLineGetTypographicBounds(line, &ascent, &descent, nil)
                let side = 0.09 * fontSize, top = 0.08 * fontSize
                let rect = CGRect(x: textRect.minX + origin.x + x0 - side, y: textRect.minY + origin.y - descent - top,
                                  width: x1 - x0 + 2 * side, height: ascent + descent + 2 * top)
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 0.2 * fontSize, cornerHeight: 0.2 * fontSize, transform: nil)) // grid: ok video pixels, relative to the font
                ctx.setFillColor(accent)
                ctx.fillPath()
            }
        }

        // The outline is the letters stroked twice as wide as it shows, under
        // the letters themselves, so it never eats into them.
        let stroke: CTFrame? = outline > 0 ? {
            let stroked = NSMutableAttributedString(attributedString: string)
            stroked.addAttribute(NSAttributedString.Key(kCTStrokeWidthAttributeName as String), value: outline * 16, range: all)
            stroked.addAttribute(NSAttributedString.Key(kCTStrokeColorAttributeName as String), value: cgColor(style.outlineColor), range: all)
            return CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(stroked), CFRange(), path, nil)
        }() : nil
        func letters() {
            ctx.setLineJoin(.round)
            if let stroke { CTFrameDraw(stroke, ctx) }
            CTFrameDraw(frame, ctx)
        }
        switch style.shadow {
        case .none:
            letters()
        case .soft:
            // A soft shadow keeps light text readable on any picture.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2 * u), blur: 8 * u, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.8)) // grid: ok video pixels
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            letters()
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        case .glow:
            // A wide glow and a tight one in the text color, then crisp letters on top.
            for blur in [0.5 * fontSize, 0.18 * fontSize] {
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: blur, color: cgColor(style.textColor, alpha: 0.9))
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                letters()
                ctx.endTransparencyLayer()
                ctx.restoreGState()
            }
            letters()
        }
        return ctx.makeImage()
    }

    // MARK: Fonts

    private struct Designs: @unchecked Sendable {
        // @unchecked: font descriptors are immutable.
        let byFile: [String: CTFontDescriptor]
    }

    /// The system's rounded, serif, and monospaced designs, read once from
    /// their files: Core Text has no public name for them.
    private static let designs: Designs = {
        var byFile: [String: CTFontDescriptor] = [:]
        for file in ["SFNSRounded", "NewYork", "SFNSMono"] {
            let url = URL(fileURLWithPath: "/System/Library/Fonts/\(file).ttf") as CFURL
            if let first = (CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor])?.first { byFile[file] = first }
        }
        return Designs(byFile: byFile)
    }()

    /// The font for `style` at `size`. System Bold is the font captions had
    /// before S-056, so their frames stay the same.
    static func font(_ style: CaptionStyle, size: CGFloat) -> CTFont {
        let system = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let file: String
        switch style.font {
        case .system:
            if style.weight == .bold, let bold = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) { return bold }
            return CTFontCreateCopyWithAttributes(system, size, nil, variation(style.weight))
        case .rounded: file = "SFNSRounded"
        case .serif: file = "NewYork"
        case .mono: file = "SFNSMono"
        case .family(let name):
            let wanted = CTFontDescriptorCreateWithAttributes([
                kCTFontFamilyNameAttribute: name,
                kCTFontTraitsAttribute: [kCTFontWeightTrait: weightTrait(style.weight)],
            ] as CFDictionary)
            guard let match = CTFontDescriptorCreateMatchingFontDescriptor(wanted, Set([kCTFontFamilyNameAttribute as String]) as CFSet)
            else { return CTFontCreateCopyWithAttributes(system, size, nil, variation(style.weight)) }
            return CTFontCreateWithFontDescriptor(match, size, nil)
        }
        guard let design = designs.byFile[file] else { return CTFontCreateCopyWithAttributes(system, size, nil, variation(style.weight)) }
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(design, variationAttributes(style.weight)), size, nil)
    }

    /// The 'wght' axis value, as the system font names its weights.
    private static func wght(_ weight: CaptionStyle.Weight) -> Int {
        switch weight {
        case .regular: 400
        case .medium: 510
        case .semibold: 590
        case .bold: 700
        case .heavy: 860
        case .black: 1000
        }
    }

    private static func variationAttributes(_ weight: CaptionStyle.Weight) -> CFDictionary {
        [kCTFontVariationAttribute: [0x7767_6874: wght(weight)]] as CFDictionary  // 'wght'
    }

    private static func variation(_ weight: CaptionStyle.Weight) -> CTFontDescriptor {
        CTFontDescriptorCreateWithAttributes(variationAttributes(weight))
    }

    private static func weightTrait(_ weight: CaptionStyle.Weight) -> CGFloat {
        switch weight {
        case .regular: 0
        case .medium: 0.23
        case .semibold: 0.3
        case .bold: 0.4
        case .heavy: 0.56
        case .black: 0.62
        }
    }

    // MARK: Helpers

    /// Where the glyphs of `range` are on `line`, left to right, from the
    /// glyph runs: string offsets do not work in right-to-left and mixed text,
    /// where a word's start can be on its right.
    static func span(of range: NSRange, in line: CTLine) -> (CGFloat, CGFloat)? {
        var lo = CGFloat.infinity, hi = -CGFloat.infinity
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var indices = [CFIndex](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetStringIndices(run, CFRange(), &indices)
            CTRunGetPositions(run, CFRange(), &positions)
            CTRunGetAdvances(run, CFRange(), &advances)
            for i in 0..<count where NSLocationInRange(indices[i], range) {
                lo = min(lo, positions[i].x)
                hi = max(hi, positions[i].x + advances[i].width)
            }
        }
        return lo < hi ? (lo, hi) : nil
    }

    private static func cgColor(_ c: RGB, alpha: Double = 1) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha) }

    private static func luminance(_ c: RGB) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
}
