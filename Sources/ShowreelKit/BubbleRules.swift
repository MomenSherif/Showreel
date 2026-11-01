import CoreGraphics
import Foundation

/// Where the Camera Bubble snaps (S-012): the four corners and four edge
/// midpoints of the visible screen, `inset` points in. All rects use one
/// coordinate space; the bubble's frame includes its shadow margin.
public enum BubbleSnap {
    /// The eight resting frames for a bubble of `size` inside `visible`.
    public static func targets(for size: CGSize, in visible: CGRect, inset: CGFloat) -> [CGRect] {
        let xs = [visible.minX + inset, visible.midX - size.width / 2, visible.maxX - inset - size.width]
        let ys = [visible.minY + inset, visible.midY - size.height / 2, visible.maxY - inset - size.height]
        var result: [CGRect] = []
        for (i, x) in xs.enumerated() {
            for (j, y) in ys.enumerated() where !(i == 1 && j == 1) { // not the center
                result.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            }
        }
        return result
    }

    /// The frame after a drag ends: the nearest target when it is within
    /// `distance` points, otherwise the frame kept inside `visible`.
    public static func snapped(_ frame: CGRect, in visible: CGRect, inset: CGFloat, distance: CGFloat) -> CGRect {
        let nearest = targets(for: frame.size, in: visible, inset: inset)
            .map { ($0, hypot($0.minX - frame.minX, $0.minY - frame.minY)) }
            .min { $0.1 < $1.1 }
        if let nearest, nearest.1 <= distance { return nearest.0 }
        return clamped(frame, in: visible)
    }

    /// Keeps the whole frame on screen.
    public static func clamped(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var f = frame
        f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        return f
    }
}

/// The Camera Bubble over time, read from an `EventLog` (S-012, S-014).
public extension EventLog {
    /// The bubble's center at `t`, or `fallback` before the first logged move.
    func bubbleCenter(at t: Double, fallback: CGPoint) -> CGPoint {
        guard let last = bubble.last(where: { $0.t <= t }) ?? bubble.first else { return fallback }
        return CGPoint(x: last.x, y: last.y)
    }

    /// True when the person hid the bubble at `t`.
    func cameraIsHidden(at t: Double) -> Bool {
        cameraHidden.contains { t >= $0.start && t < $0.end }
    }
}

/// Builds the hidden ranges while recording (S-014): hide and show may come
/// in any order and any number of times.
public struct HiddenRanges: Sendable, Equatable {
    public private(set) var ranges: [EventLog.Range] = []
    public private(set) var hiddenSince: Double?

    public init() {}

    public var isHidden: Bool { hiddenSince != nil }

    public mutating func hide(at t: Double) {
        if hiddenSince == nil { hiddenSince = t }
    }

    public mutating func show(at t: Double) {
        guard let since = hiddenSince else { return }
        if t > since { ranges.append(.init(start: since, end: t)) }
        hiddenSince = nil
    }

    /// Ends an open range when the recording stops.
    public mutating func close(at end: Double) { show(at: end) }
}
