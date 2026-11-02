import CoreGraphics
import CoreImage
import CoreText
import Synchronization
import ShowreelKit

/// Device frames drawn around the recording (S-026): Border, Browser, and
/// MacBook, each in light or dark colors. They are drawn with Core Graphics at the output size, so they
/// stay sharp at 4K, and cached, since they do not change from frame to
/// frame. Coordinates are Core Image's (bottom-left origin).
enum DeviceChrome {
    /// Everything the renderer needs for one layout.
    struct Parts: @unchecked Sendable {
        // @unchecked: CIImage is immutable and thread-safe.
        /// Drawn under the recording, or nil for no frame.
        let behind: CIImage?
        /// Cuts the recording's corners, or nil to leave them square.
        let screenMask: CIImage?
        /// The whole device's outline, for the shadow or glow.
        let outer: CGRect
        let outerRadius: CGFloat
    }

    private struct Key: Hashable {
        let frame: Style.DeviceFrame, appearance: Style.FrameAppearance, showsURLBar: Bool, url: String
        let canvas: CGSize, rect: CGRect, radius: CGFloat
    }

    private static let cache = Mutex<[Key: Parts]>([:])

    /// The frame for `style` around a recording at `rect` (Core Image
    /// coordinates) on a canvas of `size`.
    static func parts(for style: Style, rect: CGRect, radius: CGFloat, canvas size: CGSize) -> Parts {
        let key = Key(frame: style.frame, appearance: style.frameAppearance, showsURLBar: style.showsURLBar, url: style.url, canvas: size, rect: rect, radius: radius)
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let parts = make(style: style, rect: rect, radius: radius, canvas: size)
        cache.withLock { cache in
            if cache.count > 8 { cache.removeAll() }
            cache[key] = parts
        }
        return parts
    }

    /// The colors of one appearance. Video pixels, not UI: they are baked
    /// into the export, so they do not follow the app's light or dark mode.
    private struct Colors {
        let borderFill, borderStroke: CGColor
        let window, hairline, field, fieldText: CGColor
        let baseTop, baseBottom, notch: CGColor

        static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: r, green: g, blue: b, alpha: a)
        }

        static let light = Colors(
            borderFill: rgb(1, 1, 1, 0.32), borderStroke: rgb(1, 1, 1, 0.55),
            window: rgb(0.95, 0.95, 0.96), hairline: rgb(0.82, 0.82, 0.84),
            field: rgb(1, 1, 1), fieldText: rgb(0.43, 0.43, 0.45),
            // Silver aluminum.
            baseTop: rgb(0.85, 0.855, 0.875), baseBottom: rgb(0.655, 0.667, 0.69), notch: rgb(0.55, 0.56, 0.59))

        static let dark = Colors(
            borderFill: rgb(0.06, 0.06, 0.07, 0.5), borderStroke: rgb(1, 1, 1, 0.16),
            window: rgb(0.17, 0.17, 0.18), hairline: rgb(0.06, 0.06, 0.07),
            field: rgb(0.25, 0.25, 0.27), fieldText: rgb(0.66, 0.66, 0.69),
            // Space black aluminum.
            baseTop: rgb(0.27, 0.275, 0.29), baseBottom: rgb(0.13, 0.135, 0.145), notch: rgb(0.08, 0.08, 0.09))

        static func of(_ appearance: Style.FrameAppearance) -> Colors { appearance == .dark ? dark : light }
    }

    private static func make(style: Style, rect: CGRect, radius: CGFloat, canvas size: CGSize) -> Parts {
        let u = size.height / 1080
        let colors = Colors.of(style.frameAppearance)
        let chrome = CanvasLayout.chrome(for: style, canvasHeight: size.height)
        // Insets are top-left; in Core Image the top is the high y.
        var outer = CGRect(x: rect.minX - chrome.left, y: rect.minY - chrome.bottom,
                           width: rect.width + chrome.left + chrome.right, height: rect.height + chrome.top + chrome.bottom)
        switch style.frame {
        case .none:
            return Parts(behind: nil, screenMask: roundedMask(rect, radius: radius), outer: rect, outerRadius: radius)

        case .border:
            let inner = max(radius - 10 * u, 0)
            let behind = draw(size) { ctx in
                ctx.addPath(CGPath(roundedRect: outer, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.setFillColor(colors.borderFill)
                ctx.fillPath()
                ctx.addPath(CGPath(roundedRect: outer.insetBy(dx: u / 2, dy: u / 2),
                                   cornerWidth: max(radius - u / 2, 0), cornerHeight: max(radius - u / 2, 0), transform: nil))
                ctx.setStrokeColor(colors.borderStroke)
                ctx.setLineWidth(u)
                ctx.strokePath()
            }
            return Parts(behind: behind, screenMask: roundedMask(rect, radius: inner), outer: outer, outerRadius: radius)

        case .browser:
            let bar = CGRect(x: outer.minX, y: rect.maxY, width: outer.width, height: chrome.top)
            let behind = draw(size) { ctx in
                ctx.addPath(CGPath(roundedRect: outer, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.setFillColor(colors.window)
                ctx.fillPath()
                // A hairline between the bar and the page.
                ctx.setFillColor(colors.hairline)
                ctx.fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: max(u, 1)))
                // Traffic lights, at the top of the bar.
                let light = 12 * u, rowY = bar.maxY - 18 * u - light / 2
                let lights = [(1.0, 0.373, 0.341), (0.996, 0.737, 0.18), (0.157, 0.784, 0.251)]
                for (i, c) in lights.enumerated() {
                    ctx.setFillColor(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1))
                    ctx.fillEllipse(in: CGRect(x: bar.minX + 16 * u + CGFloat(i) * (light + 8 * u), y: rowY, width: light, height: light))
                }
                if style.showsURLBar {
                    let field = CGRect(x: bar.midX - bar.width * 0.25, y: bar.minY + 8 * u, width: bar.width * 0.5, height: 24 * u)
                    ctx.addPath(CGPath(roundedRect: field, cornerWidth: 6 * u, cornerHeight: 6 * u, transform: nil)) // grid: ok video pixels, not UI
                    ctx.setFillColor(colors.field)
                    ctx.fillPath()
                    if !style.url.isEmpty {
                        drawText(style.url, in: field, size: 12 * u, color: colors.fieldText, context: ctx)
                    }
                }
            }
            // The page's bottom corners follow the window; the top ones meet the bar.
            let mask = roundedMask(outer, radius: radius)?.cropped(to: rect)
            return Parts(behind: behind, screenMask: mask, outer: outer, outerRadius: radius)

        case .macBook:
            let bezel = CGRect(x: rect.minX - 18 * u, y: rect.minY - 18 * u, width: rect.width + 36 * u, height: rect.height + 40 * u)
            let base = CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: 22 * u) // grid: ok video pixels, not UI
            outer = bezel.union(base)
            let behind = draw(size) { ctx in
                ctx.addPath(CGPath(roundedRect: bezel, cornerWidth: 18 * u, cornerHeight: 18 * u, transform: nil)) // grid: ok video pixels, not UI
                ctx.setFillColor(CGColor(srgbRed: 0.067, green: 0.071, blue: 0.078, alpha: 1))
                ctx.fillPath()
                // The base: a brushed-aluminum gradient, rounded at the front.
                ctx.saveGState()
                ctx.addPath(CGPath(roundedRect: base, cornerWidth: 10 * u, cornerHeight: 10 * u, transform: nil)) // grid: ok video pixels, not UI
                ctx.clip()
                let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                          colors: [colors.baseTop, colors.baseBottom] as CFArray, locations: [0, 1])!
                ctx.drawLinearGradient(gradient, start: CGPoint(x: base.midX, y: base.maxY), end: CGPoint(x: base.midX, y: base.minY), options: [])
                ctx.restoreGState()
                // The thumb notch at the front edge.
                let notch = CGRect(x: base.midX - 60 * u, y: base.maxY - 6 * u, width: 120 * u, height: 6 * u) // grid: ok video pixels, not UI
                ctx.addPath(CGPath(roundedRect: notch, cornerWidth: 3 * u, cornerHeight: 3 * u, transform: nil)) // grid: ok video pixels, not UI
                ctx.setFillColor(colors.notch)
                ctx.fillPath()
            }
            return Parts(behind: behind, screenMask: nil, outer: outer, outerRadius: 18 * u)
        }
    }

    static func roundedMask(_ rect: CGRect, radius: CGFloat) -> CIImage? {
        guard radius > 0 else { return nil }
        return CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: rect),
            "inputRadius": radius,
            "inputColor": CIColor.white,
        ])?.outputImage
    }

    /// Draws into a clear canvas-sized bitmap.
    private static func draw(_ size: CGSize, _ body: (CGContext) -> Void) -> CIImage? {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setShouldAntialias(true)
        body(ctx)
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }

    private static func drawText(_ text: String, in field: CGRect, size: CGFloat, color: CGColor, context ctx: CGContext) {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
        let bounds = CTLineGetImageBounds(line, ctx)
        let width = min(bounds.width, field.width - 2 * size)
        ctx.saveGState()
        ctx.clip(to: field.insetBy(dx: size, dy: 0))
        ctx.textPosition = CGPoint(x: field.midX - width / 2, y: field.midY - (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
