import AppKit
import CoreImage
import ShowreelEngine
import ShowreelKit

/// The system's own cursor pictures for the drawn cursor (S-034), from the
/// largest version macOS has (10× for the arrow and I-beam), loaded once.
enum CursorSprites {
    static let system: [EventLog.Shape.Kind: CursorSprite] = {
        var sprites: [EventLog.Shape.Kind: CursorSprite] = [:]
        for kind in EventLog.Shape.Kind.allCases {
            if let sprite = sprite(cursor(for: kind)) { sprites[kind] = sprite }
        }
        return sprites
    }()

    /// The cursor styles Showreel draws (S-055), drawn once, by id.
    static let art: [String: [EventLog.Shape.Kind: CursorSprite]] = Dictionary(uniqueKeysWithValues: CursorArt.all.map { art in
        (art.id, art.sprites())
    })

    /// The pictures for `look`: the system's three shapes, a drawn style
    /// (its hand over links when it has one), the person's picture for every
    /// shape, or none. `picture` is the person's own, loaded.
    static func sprites(for look: Style.CursorLook, picture: CursorSprite?) -> [EventLog.Shape.Kind: CursorSprite] {
        switch look {
        case .system:
            return system
        case .none:
            return [:]
        case .art(let id):
            // A style this version does not know falls back to the system cursor.
            guard let drawn = art[id], !drawn.isEmpty else { return system }
            return drawn
        case .picture:
            guard let picture else { return system }
            return Dictionary(uniqueKeysWithValues: EventLog.Shape.Kind.allCases.map { ($0, picture) })
        }
    }

    /// The person's picture as a cursor: its longer side 28 points, clicking at
    /// its top-left corner or its middle.
    static func sprite(picture: CGImage, centered: Bool) -> CursorSprite {
        let w = CGFloat(picture.width), h = CGFloat(picture.height)
        let pointHeight = 28 * h / max(w, h, 1)
        return CursorSprite(image: CIImage(cgImage: picture), hotSpot: centered ? CGPoint(x: w / 2, y: h / 2) : .zero,
                            pointHeight: pointHeight)
    }

    static func cursor(for kind: EventLog.Shape.Kind) -> NSCursor {
        switch kind {
        case .arrow: .arrow
        case .iBeam: .iBeam
        case .pointer: .pointingHand
        }
    }

    static func sprite(_ cursor: NSCursor) -> CursorSprite? {
        let image = cursor.image
        guard image.size.height > 0,
              let rep = image.representations.max(by: { $0.pixelsHigh < $1.pixelsHigh }),
              let cg = (rep as? NSBitmapImageRep)?.cgImage ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let k = CGFloat(cg.height) / image.size.height
        return CursorSprite(image: CIImage(cgImage: cg), hotSpot: CGPoint(x: cursor.hotSpot.x * k, y: cursor.hotSpot.y * k),
                            pointHeight: image.size.height)
    }

    /// Which of the three the system cursor is now, matched by its size and
    /// click point. Nil for any other cursor.
    static func current() -> EventLog.Shape.Kind? {
        guard let now = NSCursor.currentSystem else { return nil }
        return signatures.first { $0.size == now.image.size && $0.hotSpot == now.hotSpot }?.kind
    }

    private static let signatures: [(kind: EventLog.Shape.Kind, size: NSSize, hotSpot: NSPoint)] =
        EventLog.Shape.Kind.allCases.map { kind in
            let cursor = cursor(for: kind)
            return (kind, cursor.image.size, cursor.hotSpot)
        }
}
