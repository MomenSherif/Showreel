import CoreGraphics
import CoreImage
import ShowreelKit

/// One cursor drawing: vector paths, made once at a high resolution so it
/// stays sharp at 3× in a zoomed 4K frame.
public struct CursorDrawing: Sendable {
    /// The picture's size, in points.
    let size: CGSize
    /// The click point, in points from the top-left corner.
    let hotSpot: CGPoint
    /// Draws in points, origin at the top left, y down.
    let draw: @Sendable (CGContext) -> Void

    /// The drawing as a picture, `pixelsPerPoint` pixels for each point.
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

    /// The drawing as the renderer draws it.
    public func sprite(pixelsPerPoint s: CGFloat = CursorArt.pixelsPerPoint) -> CursorSprite? {
        image(pixelsPerPoint: s).map {
            CursorSprite(image: CIImage(cgImage: $0), hotSpot: CGPoint(x: hotSpot.x * s, y: hotSpot.y * s),
                         pointHeight: size.height)
        }
    }
}

/// The cursor styles Showreel draws itself (S-055). A style has its arrow,
/// and may have a hand for links; without one it keeps the arrow.
public struct CursorArt: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let arrow: CursorDrawing
    public let pointer: CursorDrawing?

    init(id: String, name: String, size: CGSize, hotSpot: CGPoint, pointer: CursorDrawing? = nil,
         draw: @escaping @Sendable (CGContext) -> Void) {
        self.id = id
        self.name = name
        arrow = CursorDrawing(size: size, hotSpot: hotSpot, draw: draw)
        self.pointer = pointer
    }

    public static let all: [CursorArt] = [light, candy, hand, watermelon, dot, holo, ice, midnight]

    public static func named(_ id: String) -> CursorArt? { all.first { $0.id == id } }

    /// Pixels per point the art is drawn at: 2 (Retina) × 2 (to 4K) × 3 (largest size) × 1.33 for a zoom.
    public static let pixelsPerPoint: CGFloat = 16

    /// Every drawing of the style.
    public var drawings: [CursorDrawing] { [arrow] + (pointer.map { [$0] } ?? []) }

    /// The arrow, for a thumbnail.
    public func image(pixelsPerPoint s: CGFloat = CursorArt.pixelsPerPoint) -> CGImage? { arrow.image(pixelsPerPoint: s) }

    /// A picture for each cursor shape: the hand over links when the style
    /// has one, the arrow everywhere else.
    public func sprites() -> [EventLog.Shape.Kind: CursorSprite] {
        guard let arrow = arrow.sprite() else { return [:] }
        let hand = pointer?.sprite() ?? arrow
        return Dictionary(uniqueKeysWithValues: EventLog.Shape.Kind.allCases.map { ($0, $0 == .pointer ? hand : arrow) })
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

    // MARK: Hand

    /// A hand pointing up, the fingertip at (0, 0): 25 points wide (from
    /// x -8.5) and 24 tall.
    static func handParts() -> CGPath {
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
        return parts
    }

    /// The hand's room on its canvas, and where the fingertip sits.
    static let handSize = CGSize(width: 25 + 2 * pad, height: 25 + 2 * pad) // grid: ok cursor drawing, in points
    static let handTip = CGPoint(x: 9 + pad, y: 0.4 + pad)

    /// Lines between the folded fingers, and where the thumb meets the palm.
    static func handCreases(_ c: CGContext, color: CGColor) {
        c.setStrokeColor(color)
        c.setLineWidth(0.85)
        c.setLineCap(.round)
        for (x, top) in [(2.7, 10.2), (7.2, 11.2), (11.5, 12.2)] {
            c.move(to: CGPoint(x: x, y: top))
            c.addLine(to: CGPoint(x: x, y: top + 4.2))
        }
        c.move(to: CGPoint(x: -1.4, y: 17.2))
        c.addQuadCurve(to: CGPoint(x: 1.6, y: 20.2), control: CGPoint(x: -0.6, y: 19.6))
        c.strokePath()
    }

    /// A friendly pointing hand; the tip of the finger clicks.
    static let hand = CursorArt(id: "hand", name: "Hand", size: handSize, hotSpot: handTip) { c in
        c.saveGState()
        c.translateBy(x: handTip.x, y: handTip.y)
        let parts = handParts()
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
        handCreases(c, color: rgb(0xC98A1E))
        // A nail on the pointing finger.
        c.addPath(CGPath(roundedRect: CGRect(x: -1.7, y: 1.3, width: 3.4, height: 3.6), cornerWidth: 1.5, cornerHeight: 1.5, // grid: ok cursor drawing, in points
                         transform: nil))
        c.setFillColor(rgb(0xFFF4CC))
        c.fillPath()
        c.restoreGState()
    }

    // MARK: Watermelon

    /// A closed path through `corners`, each rounded by its radius.
    static func rounded(_ corners: [(x: CGFloat, y: CGFloat, r: CGFloat)]) -> CGPath {
        let n = corners.count
        func point(_ i: Int) -> CGPoint { let k = corners[(i + n) % n]; return CGPoint(x: k.x, y: k.y) }
        let path = CGMutablePath()
        let a = point(n - 1), b = point(0)
        path.move(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
        for i in 0..<n { path.addArc(tangent1End: point(i), tangent2End: point(i + 1), radius: corners[i].r) }
        path.closeSubpath()
        return path
    }

    static func moved(_ path: CGPath, _ transform: CGAffineTransform) -> CGPath {
        var transform = transform
        return path.copy(using: &transform) ?? path
    }

    static let melonEdge: UInt32 = 0xA3122A
    static let melonDark: UInt32 = 0xE5344F
    static let melonLight: UInt32 = 0xFF6F86

    /// Watermelon inside `shape`: darker flesh at the edge, the rind past
    /// `rind` (a path that covers the end), seeds, a shine, and a bold edge.
    static func melon(_ c: CGContext, shape: CGPath, lift: CGPoint, rind: CGPath, rindDepth: CGVector,
                      seeds: [(x: CGFloat, y: CGFloat, turn: CGFloat)], shine: [CGPoint]) {
        // A bold edge, like a sticker: drawn under, so only its outer half shows
        // and overlapping parts make one outline.
        c.addPath(shape)
        c.setStrokeColor(rgb(melonEdge))
        c.setLineWidth(3)
        c.setLineJoin(.round)
        c.strokePath()
        c.saveGState()
        c.addPath(shape)
        c.clip()
        c.addPath(shape); c.setFillColor(rgb(melonDark)); c.fillPath()
        // The lighter middle, pushed off the left edge.
        c.addPath(moved(shape, CGAffineTransform(translationX: lift.x, y: lift.y)))
        c.setFillColor(rgb(melonLight))
        c.fillPath()
        // The rind: a pale band, then the green skin with darker stripes.
        c.addPath(rind); c.setFillColor(rgb(0xD4F58A)); c.fillPath()
        let skin = CGAffineTransform(translationX: rindDepth.dx, y: rindDepth.dy)
        c.addPath(moved(rind, skin)); c.setFillColor(rgb(0x4E9A2E)); c.fillPath()
        c.saveGState()
        c.addPath(moved(rind, skin))
        c.clip()
        c.setStrokeColor(rgb(0x2E6B1D))
        c.setLineWidth(0.7)
        c.setLineCap(.round)
        let box = rind.boundingBoxOfPath
        var x = box.minX - box.height
        while x < box.maxX {
            c.move(to: CGPoint(x: x, y: box.minY))
            c.addCurve(to: CGPoint(x: x + 2.2, y: box.maxY), control1: CGPoint(x: x + 1.6, y: box.minY + box.height * 0.4),
                       control2: CGPoint(x: x - 0.8, y: box.minY + box.height * 0.6))
            x += 2.6
        }
        c.strokePath()
        c.restoreGState()
        // Seeds, each with a glint.
        for seed in seeds {
            c.saveGState()
            c.translateBy(x: seed.x, y: seed.y)
            c.rotate(by: seed.turn * .pi / 180)
            let drop = CGMutablePath()
            drop.move(to: CGPoint(x: 0, y: -1.3))
            drop.addCurve(to: CGPoint(x: 0, y: 1.2), control1: CGPoint(x: 1.3, y: -0.5), control2: CGPoint(x: 1, y: 1.2))
            drop.addCurve(to: CGPoint(x: 0, y: -1.3), control1: CGPoint(x: -1, y: 1.2), control2: CGPoint(x: -1.3, y: -0.5))
            c.addPath(drop); c.setFillColor(rgb(0x3D1C12)); c.fillPath()
            c.setFillColor(rgb(0xFFFFFF, 0.7))
            c.fillEllipse(in: CGRect(x: -0.55, y: -0.6, width: 0.5, height: 0.6)) // grid: ok cursor drawing, in points
            c.restoreGState()
        }
        // A wet shine: a long stroke and a dot.
        c.setStrokeColor(rgb(0xFFFFFF, 0.92))
        c.setLineCap(.round)
        c.setLineWidth(1.6)
        if shine.count >= 2 {
            c.move(to: shine[0])
            c.addLine(to: shine[1])
            c.strokePath()
        }
        if shine.count >= 3 {
            c.setFillColor(rgb(0xFFFFFF, 0.92))
            c.fillEllipse(in: CGRect(x: shine[2].x - 0.8, y: shine[2].y - 0.8, width: 1.6, height: 1.6)) // grid: ok cursor drawing, in points
        }
        c.restoreGState()
    }

    /// A chunky arrow made of watermelon, the rind on its tail, and a
    /// watermelon hand for links. The tips click.
    static let watermelon = CursorArt(id: "watermelon", name: "Watermelon", size: CGSize(width: 20 + 2 * pad, height: 24 + 2 * pad),
                                      hotSpot: CGPoint(x: pad + 0.4, y: pad + 0.6), pointer: melonHand) { c in
        c.translateBy(x: pad, y: pad)
        let arrow = rounded([(0, 0, 0.9), (0.6, 19.6, 0.9), (6.2, 15.6, 0.5), (10.4, 23.4, 1.6), (16.4, 20.2, 1.6),
                             (12.3, 12.6, 0.5), (19.6, 11.6, 0.9)])
        // Across the tail, about two thirds of the way down it, bowed toward the tip.
        let rind = CGMutablePath()
        rind.move(to: CGPoint(x: 2, y: 23.5))
        rind.addQuadCurve(to: CGPoint(x: 19.5, y: 14.2), control: CGPoint(x: 12.4, y: 16.4))
        rind.addLine(to: CGPoint(x: 30, y: 30))
        rind.addLine(to: CGPoint(x: 2, y: 30))
        rind.closeSubpath()
        melon(c, shape: arrow, lift: CGPoint(x: 1.5, y: -0.3), rind: rind, rindDepth: CGVector(dx: 0.55, dy: 1),
              seeds: [(4.6, 7.2, -20), (8.8, 8.6, 10), (5.2, 12.6, -35), (12.6, 10.6, 25), (9.4, 13.8, 0), (3.2, 16, -15),
                      (14.6, 10.4, 40)],
              shine: [CGPoint(x: 3.4, y: 4.6), CGPoint(x: 9, y: 7.8), CGPoint(x: 12, y: 9.4)])
    }

    /// The watermelon pointing hand.
    static let melonHand = CursorDrawing(size: handSize, hotSpot: handTip) { c in
        c.translateBy(x: handTip.x, y: handTip.y)
        let rind = CGMutablePath()
        rind.move(to: CGPoint(x: -10, y: 19.6))
        rind.addQuadCurve(to: CGPoint(x: 18, y: 19.6), control: CGPoint(x: 4, y: 17.4))
        rind.addLine(to: CGPoint(x: 18, y: 30))
        rind.addLine(to: CGPoint(x: -10, y: 30))
        rind.closeSubpath()
        melon(c, shape: handParts(), lift: CGPoint(x: 1.2, y: -0.2), rind: rind, rindDepth: CGVector(dx: 0, dy: 1.2),
              seeds: [(-0.4, 6.2, -10), (0.6, 11.4, 15), (-1.6, 15.6, -25), (5, 13.6, 5), (9.4, 14.8, -10), (13.2, 15.4, 20),
                      (3.4, 17.6, 30)],
              shine: [CGPoint(x: 1.1, y: 2.4), CGPoint(x: 1.1, y: 6.4), CGPoint(x: 9.6, y: 10.8)])
        c.saveGState()
        c.addPath(handParts())
        c.clip()
        handCreases(c, color: rgb(melonEdge, 0.55))
        c.restoreGState()
    }

    // MARK: 3D pixel

    /// A pixel arrow, one character a pixel: its tip is the top-left corner.
    static let pixelArrow = [
        "X", "XX", "XXX", "XXXX", "XXXXX", "XXXXXX", "XXXXXXX", "XXXXXXXX", "XXXXXXXXX", "XXXXXXXXXX",
        "XXXXXXXXXXX", "XXXXXXXXXXXX", "XXXXXXX", "XXX XXXX", "XX  XXXX", "X    XXXX", "     XXXX",
        "      XXXX", "      XXX",
    ]

    /// A pixel hand pointing up; the finger's top is at x 6 (in pixels).
    static let pixelHand = [
        "     XX", "    XXXX", "    XXXX", "    XXXX", "    XXXX", "    XXXXXX", "    XXXXXXXXX",
        "    XXXXXXXXXXX", "XX  XXXXXXXXXXXX", "XXX XXXXXXXXXXXX", "XXXXXXXXXXXXXXXX", " XXXXXXXXXXXXXXX",
        " XXXXXXXXXXXXXXX", "  XXXXXXXXXXXXXX", "  XXXXXXXXXXXXXX", "   XXXXXXXXXXXXX", "   XXXXXXXXXXXX",
        "    XXXXXXXXXXX", "    XXXXXXXXXXX", "    XXXXXXXXXXX",
    ]

    /// Lines between the hand's folded fingers, in pixels: (x, from y, to y).
    static let pixelHandCreases: [(x: CGFloat, top: CGFloat, bottom: CGFloat)] = [(8, 6, 10), (11, 7, 11), (4, 10, 13)]

    /// The filled pixels as one outline, `cell` points a pixel.
    static func pixels(_ rows: [String], cell: CGFloat) -> CGPath {
        var shape = CGPath(rect: .zero, transform: nil)
        for (y, row) in rows.enumerated() {
            var x = 0
            let chars = Array(row)
            while x < chars.count {
                guard chars[x] == "X" else { x += 1; continue }
                var end = x
                while end < chars.count, chars[end] == "X" { end += 1 }
                // A hair taller, so rows overlap and join without a seam.
                let run = CGPath(rect: CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell - 0.01, width: CGFloat(end - x) * cell,
                                              height: cell + 0.02), transform: nil)
                shape = shape.union(run)
                x = end
            }
        }
        return shape
    }

    /// The colors of one 3D pixel style.
    struct PixelLook: Sendable {
        /// The face, from its top-left to its bottom-right.
        var face: [UInt32]
        /// The sides, from just under the face to the back: stripes that
        /// repeat, or one smooth blend from the first to the last.
        var sides: [UInt32]
        var striped = false
        var edge: UInt32
        /// How bright the shine across the face is.
        var shine: CGFloat
    }

    /// Pixels drawn as a thick block: the sides stacked down and to the right,
    /// a glossy face, a thin edge, and a shine across it.
    static func pixelBlock(_ c: CGContext, rows: [String], look: PixelLook, creases: [(x: CGFloat, top: CGFloat, bottom: CGFloat)]) {
        let cell: CGFloat = 1.1
        let face = pixels(rows, cell: cell)
        let box = face.boundingBoxOfPath
        let layers = 9, step: CGFloat = 0.3
        for k in stride(from: layers, through: 1, by: -1) {
            c.addPath(moved(face, CGAffineTransform(translationX: CGFloat(k) * step, y: CGFloat(k) * step)))
            c.setFillColor(look.striped ? rgb(look.sides[(k - 1) % look.sides.count])
                : blend(look.sides[0], look.sides[look.sides.count - 1], CGFloat(k - 1) / CGFloat(layers - 1)))
            c.fillPath()
        }
        c.saveGState()
        c.addPath(face)
        c.clip()
        c.drawLinearGradient(gradient(look.face), start: CGPoint(x: box.minX, y: box.minY),
                             end: CGPoint(x: box.maxX, y: box.maxY), options: [])
        // A broad soft band and a thin bright line, across from the top right.
        let band = CGMutablePath()
        let a = box.width * 0.25, b = box.width * 0.55
        band.addLines(between: [CGPoint(x: a, y: 0), CGPoint(x: b, y: 0), CGPoint(x: 0, y: b), CGPoint(x: 0, y: a)])
        band.closeSubpath()
        c.addPath(band)
        c.setFillColor(rgb(0xFFFFFF, 0.35 * look.shine))
        c.fillPath()
        c.setStrokeColor(rgb(0xFFFFFF, 0.8 * look.shine))
        c.setLineWidth(0.7)
        c.move(to: CGPoint(x: b + 1.2, y: 0))
        c.addLine(to: CGPoint(x: 0, y: b + 1.2))
        c.strokePath()
        // The lines between the folded fingers, one pixel wide.
        c.setFillColor(rgb(look.edge, 0.7))
        for crease in creases {
            c.fill(CGRect(x: crease.x * cell, y: crease.top * cell, width: cell * 0.5, height: (crease.bottom - crease.top) * cell))
        }
        c.restoreGState()
        c.addPath(face)
        c.setStrokeColor(rgb(look.edge))
        c.setLineWidth(0.5)
        c.setLineJoin(.miter)
        c.strokePath()
    }

    /// Between two colors: 0 is `a`, 1 is `b`.
    static func blend(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> CGColor {
        func part(_ c: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((c >> shift) & 0xFF) / 255 }
        func mix(_ shift: UInt32) -> CGFloat { part(a, shift) + (part(b, shift) - part(a, shift)) * t }
        return CGColor(srgbRed: mix(16), green: mix(8), blue: mix(0), alpha: 1)
    }

    /// A 3D pixel style: the arrow, and the hand for links.
    static func pixelStyle(id: String, name: String, look: PixelLook) -> CursorArt {
        let hand = CursorDrawing(size: CGSize(width: 16 * 1.1 + 3 + 2 * pad, height: 20 * 1.1 + 3 + 2 * pad),
                                 hotSpot: CGPoint(x: 6 * 1.1 + pad, y: pad + 0.2)) { c in
            c.translateBy(x: pad, y: pad)
            pixelBlock(c, rows: pixelHand, look: look, creases: pixelHandCreases)
        }
        return CursorArt(id: id, name: name, size: CGSize(width: 12 * 1.1 + 3 + 2 * pad, height: 19 * 1.1 + 3 + 2 * pad), // grid: ok cursor drawing, in points
                         hotSpot: CGPoint(x: pad + 0.2, y: pad + 0.2), pointer: hand) { c in
            c.translateBy(x: pad, y: pad)
            pixelBlock(c, rows: pixelArrow, look: look, creases: [])
        }
    }

    /// Pastel pink, butter, and sky, with rainbow sides.
    static let holo = pixelStyle(id: "holo", name: "Holographic", look: PixelLook(
        face: [0xFFC2E6, 0xFFF1B8, 0xBDF4FF], sides: [0x7FE3F5, 0xFF8AD0, 0xFFE27A], striped: true, edge: 0xE86AB8, shine: 1))

    /// Clear blue ice.
    static let ice = pixelStyle(id: "ice", name: "Ice", look: PixelLook(
        face: [0xEFFCFF, 0xA8E6FF, 0x5CC4F5], sides: [0x3AA8EC, 0x0F5FA6], edge: 0x1580D0, shine: 1))

    /// Glossy black with neon sides.
    static let midnight = pixelStyle(id: "midnight", name: "Midnight", look: PixelLook(
        face: [0x3A2C66, 0x0D0B1C, 0x05050C], sides: [0xFF5FD2, 0x6E5CFF], edge: 0xC58BFF, shine: 0.7))
}
