import CoreGraphics
import CoreImage

/// The cursors Showreel draws itself (S-055): vector drawings, made once at
/// a high resolution so they stay sharp at 3× in a zoomed 4K frame.
public struct CursorArt: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// The picture's size, in points.
    let size: CGSize
    /// The click point, in points from the top-left corner.
    let hotSpot: CGPoint
    /// Draws in points, origin at the top left, y down.
    let draw: @Sendable (CGContext) -> Void

    public static let all: [CursorArt] = [light, candy, hand, watermelon, dot]

    public static func named(_ id: String) -> CursorArt? { all.first { $0.id == id } }

    /// Pixels per point the art is drawn at: 2 (Retina) × 2 (to 4K) × 3 (largest size) × 1.33 for a zoom.
    public static let pixelsPerPoint: CGFloat = 16

    /// The art as a picture, `pixelsPerPoint` pixels for each point.
    public func image(pixelsPerPoint s: CGFloat = CursorArt.pixelsPerPoint) -> CGImage? {
        let w = Int((size.width * s).rounded(.up)), h = Int((size.height * s).rounded(.up))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: s, y: -s)
        context.setShouldAntialias(true)
        // A soft shadow below, like the system cursor's. Shadow offsets ignore
        // the flip, so down is negative.
        context.setShadow(offset: CGSize(width: 0, height: -0.8 * s), blur: 2.2 * s, // grid: ok cursor drawing, in points
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        draw(context)
        context.endTransparencyLayer()
        return context.makeImage()
    }

    /// The art as the renderer draws it.
    public func sprite(pixelsPerPoint s: CGFloat = CursorArt.pixelsPerPoint) -> CursorSprite? {
        image(pixelsPerPoint: s).map {
            CursorSprite(image: CIImage(cgImage: $0), hotSpot: CGPoint(x: hotSpot.x * s, y: hotSpot.y * s),
                         pointHeight: size.height)
        }
    }
}

// MARK: The drawings

extension CursorArt {
    /// Room around each drawing for its outline and shadow, in points.
    static let pad: CGFloat = 4

    /// An arrow with its tip at (0, 0), about 19 points tall.
    static func arrowPath(at origin: CGPoint) -> CGPath {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 17), CGPoint(x: 4.3, y: 13.1), CGPoint(x: 7, y: 19.3),
            CGPoint(x: 9.6, y: 18.2), CGPoint(x: 7, y: 12.3), CGPoint(x: 12.6, y: 12.3),
        ]
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) })
        path.closeSubpath()
        return path
    }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func gradient(_ colors: [UInt32]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map { rgb($0) } as CFArray,
                   locations: nil)!
    }

    /// White with a dark edge: the system arrow turned around, for dark videos.
    static let light = CursorArt(id: "light", name: "Light", size: CGSize(width: 13 + 2 * pad, height: 20 + 2 * pad), // grid: ok cursor drawing, in points
                                 hotSpot: CGPoint(x: pad, y: pad)) { c in
        let path = arrowPath(at: CGPoint(x: pad, y: pad))
        c.addPath(path)
        c.setFillColor(rgb(0xFFFFFF))
        c.fillPath()
        c.addPath(path)
        c.setStrokeColor(rgb(0x111111))
        c.setLineWidth(1.3)
        c.setLineJoin(.round)
        c.strokePath()
    }

    /// A pink-to-violet arrow with a white edge.
    static let candy = CursorArt(id: "candy", name: "Candy", size: CGSize(width: 13 + 2 * pad, height: 20 + 2 * pad), // grid: ok cursor drawing, in points
                                 hotSpot: CGPoint(x: pad, y: pad)) { c in
        let path = arrowPath(at: CGPoint(x: pad, y: pad))
        c.addPath(path)
        c.setStrokeColor(rgb(0xFFFFFF))
        c.setLineWidth(2.6)
        c.setLineJoin(.round)
        c.strokePath()
        c.saveGState()
        c.addPath(path)
        c.clip()
        c.drawLinearGradient(gradient([0xFF6AB0, 0xA35BFF, 0x5B6BFF]), start: CGPoint(x: pad, y: pad),
                             end: CGPoint(x: pad + 8, y: pad + 19), options: [])
        c.restoreGState()
    }

    /// A round, see-through spot with a white ring; it clicks at its middle.
    static let dot = CursorArt(id: "dot", name: "Spot", size: CGSize(width: 22 + 2 * pad, height: 22 + 2 * pad), // grid: ok cursor drawing, in points
                               hotSpot: CGPoint(x: 11 + pad, y: 11 + pad)) { c in
        let ring = CGRect(x: pad + 1.25, y: pad + 1.25, width: 19.5, height: 19.5) // grid: ok cursor drawing, in points
        c.setFillColor(rgb(0x1C1C1E, 0.38))
        c.fillEllipse(in: ring)
        c.setStrokeColor(rgb(0xFFFFFF, 0.95))
        c.setLineWidth(2.5)
        c.strokeEllipse(in: ring)
    }

    /// A slice of watermelon; its tip clicks.
    static let watermelon = CursorArt(id: "watermelon", name: "Watermelon", size: CGSize(width: 18 + 2 * pad, height: 23 + 2 * pad), // grid: ok cursor drawing, in points
                                      hotSpot: CGPoint(x: pad, y: pad)) { c in
        let apex = CGPoint(x: pad, y: pad)
        // y is down, so angles turn clockwise from the right.
        let from = 47.0 * .pi / 180, to = 86.0 * .pi / 180
        func slice(_ r: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.move(to: apex)
            path.addArc(center: apex, radius: r, startAngle: from, endAngle: to, clockwise: false)
            path.closeSubpath()
            return path
        }
        c.setLineJoin(.round)
        // A dark edge first, so the slice reads on a white page.
        c.addPath(slice(23))
        c.setStrokeColor(rgb(0x1E4D1A))
        c.setLineWidth(1.4)
        c.strokePath()
        c.addPath(slice(23)); c.setFillColor(rgb(0x2F8A2B)); c.fillPath()
        c.addPath(slice(21.2)); c.setFillColor(rgb(0x8FD14F)); c.fillPath()
        c.addPath(slice(19.9)); c.setFillColor(rgb(0xF3F9D2)); c.fillPath()
        c.saveGState()
        c.addPath(slice(18.6))
        c.clip()
        c.drawRadialGradient(gradient([0xFF5A6E, 0xF2334B]), startCenter: apex, startRadius: 0,
                             endCenter: apex, endRadius: 18.6, options: [])
        c.restoreGState()
        // Seeds, pointing at the tip.
        for (r, degrees) in [(8.5, 63.0), (12.2, 54.0), (12.6, 74.0), (15.6, 63.5), (15.2, 80.0)] {
            let a = degrees * .pi / 180
            c.saveGState()
            c.translateBy(x: apex.x + r * cos(a), y: apex.y + r * sin(a))
            c.rotate(by: a + .pi / 2)
            let seed = CGMutablePath()
            seed.move(to: CGPoint(x: 0, y: -1.5))
            seed.addCurve(to: CGPoint(x: 0, y: 1.4), control1: CGPoint(x: 1.5, y: -0.6), control2: CGPoint(x: 1.1, y: 1.4))
            seed.addCurve(to: CGPoint(x: 0, y: -1.5), control1: CGPoint(x: -1.1, y: 1.4), control2: CGPoint(x: -1.5, y: -0.6))
            c.addPath(seed)
            c.setFillColor(rgb(0x2A1A14))
            c.fillPath()
            c.restoreGState()
        }
        // A sheen along the cut.
        c.saveGState()
        c.addPath(slice(18.6))
        c.clip()
        c.setStrokeColor(rgb(0xFFFFFF, 0.35))
        c.setLineWidth(1.2)
        c.move(to: CGPoint(x: apex.x + 3 * cos(from) + 0.6, y: apex.y + 3 * sin(from) - 0.6))
        c.addLine(to: CGPoint(x: apex.x + 16 * cos(from) + 0.6, y: apex.y + 16 * sin(from) - 0.6))
        c.strokePath()
        c.restoreGState()
    }

    /// A friendly pointing hand; the tip of the finger clicks.
    static let hand = CursorArt(id: "hand", name: "Hand", size: CGSize(width: 25 + 2 * pad, height: 25 + 2 * pad), // grid: ok cursor drawing, in points
                                hotSpot: CGPoint(x: 9 + pad, y: 0.4 + pad)) { c in
        // Drawn with the fingertip at (0, 0).
        c.saveGState()
        c.translateBy(x: 9 + pad, y: 0.4 + pad)
        let parts = CGMutablePath()
        // The pointing finger.
        parts.addRoundedRect(in: CGRect(x: -3.2, y: 0, width: 6.4, height: 16), cornerWidth: 3.2, cornerHeight: 3.2) // grid: ok cursor drawing, in points
        // The folded fingers, one knuckle each.
        parts.addRoundedRect(in: CGRect(x: 2.2, y: 7.6, width: 5.4, height: 9), cornerWidth: 2.7, cornerHeight: 2.7) // grid: ok cursor drawing, in points
        parts.addRoundedRect(in: CGRect(x: 6.8, y: 8.6, width: 5.2, height: 8.4), cornerWidth: 2.6, cornerHeight: 2.6) // grid: ok cursor drawing, in points
        parts.addRoundedRect(in: CGRect(x: 11.1, y: 10, width: 4.6, height: 7.6), cornerWidth: 2.3, cornerHeight: 2.3) // grid: ok cursor drawing, in points
        // The palm.
        parts.addRoundedRect(in: CGRect(x: -3.2, y: 12, width: 18.9, height: 12), cornerWidth: 5.5, cornerHeight: 5.5) // grid: ok cursor drawing, in points
        // The thumb, reaching up and out from the palm's left side.
        let thumb = CGPath(roundedRect: CGRect(x: -4.6, y: -2.6, width: 9.2, height: 5.2), cornerWidth: 2.6, cornerHeight: 2.6, // grid: ok cursor drawing, in points
                           transform: nil)
        parts.addPath(thumb, transform: CGAffineTransform(translationX: -3.6, y: 15.2).rotated(by: 40 * .pi / 180))

        c.setLineJoin(.round)
        c.addPath(parts)
        c.setStrokeColor(rgb(0x7A4A12))
        c.setLineWidth(2.4)
        c.strokePath()
        c.saveGState()
        c.addPath(parts)
        c.clip()
        c.drawLinearGradient(gradient([0xFFE27A, 0xFFC53D]), start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 24), options: [])
        c.restoreGState()
        // Lines between the folded fingers, and where the thumb meets the palm.
        c.setStrokeColor(rgb(0xC98A1E))
        c.setLineWidth(0.85)
        c.setLineCap(.round)
        for (x, top) in [(2.7, 10.2), (7.2, 11.2), (11.5, 12.2)] {
            c.move(to: CGPoint(x: x, y: top))
            c.addLine(to: CGPoint(x: x, y: top + 4.2))
        }
        c.move(to: CGPoint(x: -1.4, y: 17.2))
        c.addQuadCurve(to: CGPoint(x: 1.6, y: 20.2), control: CGPoint(x: -0.6, y: 19.6))
        c.strokePath()
        // A nail on the pointing finger.
        c.addPath(CGPath(roundedRect: CGRect(x: -1.7, y: 1.3, width: 3.4, height: 3.6), cornerWidth: 1.5, cornerHeight: 1.5, // grid: ok cursor drawing, in points
                         transform: nil))
        c.setFillColor(rgb(0xFFF4CC))
        c.fillPath()
        c.restoreGState()
    }
}
