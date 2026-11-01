import CoreGraphics

/// The part of the recording that stays after cropping (S-025), normalized
/// to the recording (0...1, top-left origin, like the event log).
public struct CropRect: Codable, Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    /// The whole recording.
    public static let full = CropRect(x: 0, y: 0, width: 1, height: 1)
    /// The smallest crop, as a share of each side, so it stays usable.
    public static let minSide = 0.1

    public var isFull: Bool { self == .full }

    /// Where a point of the recording (a click, a zoom focus, the bubble)
    /// lands in the cropped frame, or nil when it was cut away.
    public func map(_ point: CGPoint) -> CGPoint? {
        let p = CGPoint(x: (point.x - x) / width, y: (point.y - y) / height)
        // A hair of tolerance: the crop's own edges must map to 0 and 1.
        let edge = -1e-9...(1 + 1e-9)
        guard edge.contains(p.x), edge.contains(p.y) else { return nil }
        return CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }

    /// The same, but kept inside the frame: for a zoom focus near a cut edge.
    public func mapClamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max((point.x - x) / width, 0), 1), y: min(max((point.y - y) / height, 0), 1))
    }

    /// The crop in pixels of a `source`-sized recording (top-left origin), on whole pixels.
    public func pixels(of source: CGSize) -> CGRect {
        CGRect(x: (x * source.width).rounded(), y: (y * source.height).rounded(),
               width: (width * source.width).rounded(), height: (height * source.height).rounded())
    }

    /// What a crop handle moves.
    public enum Handle: CaseIterable, Sendable {
        case topLeading, top, topTrailing, leading, trailing, bottomLeading, bottom, bottomTrailing, move
    }

    /// The crop after dragging `handle` by `dx`, `dy` (normalized). Edges stop
    /// at the recording and at `minSide`; moving keeps the size.
    public func dragging(_ handle: Handle, dx: Double, dy: Double) -> CropRect {
        var left = x, top = y, right = x + width, bottom = y + height
        switch handle {
        case .move:
            let nx = min(max(x + dx, 0), 1 - width), ny = min(max(y + dy, 0), 1 - height)
            return CropRect(x: nx, y: ny, width: width, height: height)
        case .topLeading: left += dx; top += dy
        case .top: top += dy
        case .topTrailing: right += dx; top += dy
        case .leading: left += dx
        case .trailing: right += dx
        case .bottomLeading: left += dx; bottom += dy
        case .bottom: bottom += dy
        case .bottomTrailing: right += dx; bottom += dy
        }
        left = min(max(left, 0), right - Self.minSide)
        top = min(max(top, 0), bottom - Self.minSide)
        right = max(min(right, 1), left + Self.minSide)
        bottom = max(min(bottom, 1), top + Self.minSide)
        return CropRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
