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
