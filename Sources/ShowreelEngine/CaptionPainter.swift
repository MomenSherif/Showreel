import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Synchronization
import ShowreelKit

/// Draws the caption on screen (S-041): bold system text, centered, in an
/// optional box, with the spoken word on a colored pill. Drawn with Core Text
/// at the output size, so it is sharp at 4K, and cached per caption and word,
/// since it changes only a few times a second. Core Image coordinates.
enum CaptionPainter {
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
        guard let image = draw(caption, word: word, style: style, canvas: size, language: captions.language) else { return nil }
        cache.withLock { cache in
            if cache.count > 24 { cache.removeAll() }
            cache[key] = Image(image: image)
        }
        return image
    }

    /// Sizes are set for a 1080-pixel canvas and follow its shorter side, so
    /// a tall video has captions as big as a wide one.
    static func unit(_ canvas: CGSize) -> CGFloat { min(canvas.width, canvas.height) / 1080 }

    private static func draw(_ caption: Caption, word: Int?, style: CaptionStyle, canvas: CGSize, language: String) -> CIImage? {
        let u = unit(canvas)
        let fontSize = 46 * u * CGFloat(min(max(style.size, CaptionStyle.sizeRange.lowerBound), CaptionStyle.sizeRange.upperBound))
        guard let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil) else { return nil }

        // The words as one string, remembering where each one is.
        var text = ""
        var ranges: [NSRange] = []
        for (i, w) in caption.words.enumerated() {
            if i > 0 { text += " " }
            let start = (text as NSString).length
            text += w.text.trimmingCharacters(in: .whitespaces)
            ranges.append(NSRange(location: start, length: (text as NSString).length - start))
        }
        let ink = textColor(style.box)
        let pill = style.highlightColor
        let onPill = luminance(pill) > 0.55 ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

        let string = NSMutableAttributedString(string: text)
        let all = NSRange(location: 0, length: string.length)
        // Arabic reads from the right even when a line starts with an English
        // word (S-054); English words inside it keep their own order.
        var alignment = CTTextAlignment.center
        var direction = caption.isRightToLeft(language: language) ? CTWritingDirection.rightToLeft : .leftToRight
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
        string.addAttribute(NSAttributedString.Key(kCTFontAttributeName as String), value: font, range: all)
        string.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: ink, range: all)
        string.addAttribute(NSAttributedString.Key(kCTParagraphStyleAttributeName as String), value: paragraph, range: all)
        if let word, ranges.indices.contains(word) {
            string.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: onPill, range: ranges[word])
        }

        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let maxWidth = canvas.width * 0.84
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil,
                                                               CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
        let textSize = CGSize(width: ceil(fit.width) + 2, height: ceil(fit.height))
        let pad = CGSize(width: (0.5 * fontSize).rounded(), height: (0.26 * fontSize).rounded())
        let box = CGSize(width: textSize.width + 2 * pad.width, height: textSize.height + 2 * pad.height)

        let width = Int(box.width.rounded(.up)), height = Int(box.height.rounded(.up))
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Renderer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if let fill = boxColor(style.box) {
            ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: 0.3 * fontSize, cornerHeight: 0.3 * fontSize, transform: nil)) // grid: ok video pixels, relative to the font
            ctx.setFillColor(fill)
            ctx.fillPath()
        }
        let textRect = CGRect(x: pad.width, y: pad.height, width: textSize.width, height: textSize.height)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: textRect, transform: nil), nil)

        // The pill behind the spoken word, on each line the word is on.
        if let word, ranges.indices.contains(word) {
            let range = ranges[word]
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
                ctx.setFillColor(CGColor(srgbRed: pill.r, green: pill.g, blue: pill.b, alpha: 1))
                ctx.fillPath()
            }
        }
        if style.box == .none {
            // No box: a soft shadow keeps white text readable on any picture.
            ctx.setShadow(offset: CGSize(width: 0, height: -2 * u), blur: 8 * u, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.8)) // grid: ok video pixels
        }
        CTFrameDraw(frame, ctx)
        guard let picture = ctx.makeImage() else { return nil }

        let margin = 0.06 * canvas.height
        let x = ((canvas.width - box.width) / 2).rounded()
        let y = style.position == .bottom ? margin.rounded() : (canvas.height - margin - box.height).rounded()
        return CIImage(cgImage: picture).transformed(by: CGAffineTransform(translationX: x, y: y))
    }

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

    private static func textColor(_ box: CaptionStyle.Box) -> CGColor {
        box == .light ? CGColor(srgbRed: 0.08, green: 0.08, blue: 0.1, alpha: 1) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    private static func boxColor(_ box: CaptionStyle.Box) -> CGColor? {
        switch box {
        case .none: nil
        case .dark: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.68)
        case .light: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92)
        }
    }

    private static func luminance(_ c: RGB) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
}
