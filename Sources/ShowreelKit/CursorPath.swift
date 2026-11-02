import CoreGraphics
import Foundation

/// The recorded cursor (events.json, 60 Hz while it moves), read at any
/// time. Positions are normalized to the recording, top-left origin.
public struct CursorPath: Equatable, Sendable {
    /// Oldest first.
    public var points: [EventLog.Point]

    public init(_ points: [EventLog.Point] = []) {
        self.points = points.sorted { $0.t < $1.t }
    }

    public var isEmpty: Bool { points.isEmpty }

    /// Where the cursor was at `t`, between two samples on the line between
    /// them. Before the first sample it is at the first; after the last, at the last.
    public func position(at t: Double) -> CGPoint? {
        guard let first = points.first, let last = points.last else { return nil }
        if t <= first.t { return CGPoint(x: first.x, y: first.y) }
        if t >= last.t { return CGPoint(x: last.x, y: last.y) }
        // The first sample after t.
        var lo = 0, hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].t <= t { lo = mid + 1 } else { hi = mid }
        }
        let a = points[lo - 1], b = points[lo]
        let f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// The average position over `window` seconds around `t`: calm enough for
    /// a zoom to follow without shaking (S-031; S-033 adds the spring).
    public func smoothed(at t: Double, window: Double = 0.8) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let steps = 9
        var x = 0.0, y = 0.0
        for i in 0..<steps {
            let p = position(at: t - window / 2 + window * Double(i) / Double(steps - 1))!
            x += p.x; y += p.y
        }
        return CGPoint(x: x / Double(steps), y: y / Double(steps))
    }
}
