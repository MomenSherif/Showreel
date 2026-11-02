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

/// The drawn cursor at one moment (S-034).
public struct CursorFrame: Equatable, Sendable {
    /// Normalized to the recording, top-left origin.
    public var position: CGPoint
    public var shape: EventLog.Shape.Kind
    /// 0...1: it fades out when idle (if asked) and while it is away.
    public var opacity: Double
}

/// The cursor to draw over a whole recording (S-034): its path smoothed by
/// a critically damped spring, its shape, and when it fades.
public struct CursorTrack: Equatable, Sendable {
    /// Seconds without moving before an idle cursor fades out.
    public static let idleAfter = 2.0
    /// Seconds a fade takes.
    public static let fade = 0.3

    let raw: CursorPath
    let path: CursorPath
    let shapes: [EventLog.Shape]
    let away: [EventLog.Range]
    let hidesWhenIdle: Bool

    public static let none = CursorTrack(log: nil, duration: 0)

    /// `smoothing` 0 draws the cursor where it was; 1 glides the most.
    public init(log: EventLog?, duration: Double, smoothing: Double = 0.5, hidesWhenIdle: Bool = false) {
        raw = CursorPath(log?.cursor ?? [])
        shapes = (log?.cursorShapes ?? []).sorted { $0.t < $1.t }
        away = log?.cursorAway ?? []
        self.hidesWhenIdle = hidesWhenIdle
        path = Self.smoothed(raw, duration: duration, smoothing: min(max(smoothing, 0), 1))
    }

    /// The spring's natural frequency for a smoothing amount: 40 rad/s
    /// (barely there) down to 6 (a slow glide).
    public static func omega(smoothing: Double) -> Double { 40 * pow(0.15, smoothing) }

    static func smoothed(_ raw: CursorPath, duration: Double, smoothing: Double) -> CursorPath {
        guard smoothing > 0, let first = raw.points.first, let last = raw.points.last else { return raw }
        let omega = omega(smoothing: smoothing), dt = 1 / ZoomPath.rate
        let end = max(min(duration, last.t + 2), last.t)
        var x = Spring(value: first.x), y = Spring(value: first.y)
        var points: [EventLog.Point] = []
        points.reserveCapacity(Int((end - first.t) * ZoomPath.rate) + 2)
        var t = first.t
        while t <= end + dt / 2 {
            if let p = raw.position(at: t) { // grid: ok time, not layout
                x.step(toward: p.x, omega: omega, dt: dt)
                y.step(toward: p.y, omega: omega, dt: dt)
            }
            points.append(EventLog.Point(t: t, x: x.value, y: y.value))
            t += dt
        }
        return CursorPath(points)
    }

    /// The cursor at source time `t`, or nil before it was first seen.
    public func frame(at t: Double) -> CursorFrame? {
        guard let first = raw.points.first, t >= first.t - 0.001, let position = path.position(at: t) else { return nil } // grid: ok time, not layout
        let shape = shapes.last { $0.t <= t }?.kind ?? .arrow
        var opacity = 1.0
        // Away: fade out over the start of the range and back in at its end.
        if let range = away.first(where: { $0.start <= t && t <= $0.end }) {
            opacity = min(opacity, max(0, 1 - (t - range.start) / Self.fade))
        }
        if hidesWhenIdle, let moved = raw.points.last(where: { $0.t <= t })?.t {
            let idle = t - moved - Self.idleAfter
            if idle > 0 { opacity = min(opacity, max(0, 1 - idle / Self.fade)) }
        }
        return CursorFrame(position: position, shape: shape, opacity: opacity)
    }
}

/// The marks drawn at clicks (S-035): each one shows for `length` seconds
/// after its click.
public struct ClickMarks: Equatable, Sendable {
    public static let length = 0.4

    /// One mark now: where, and how far through (0 just clicked, 1 gone).
    public struct Mark: Equatable, Sendable {
        public var position: CGPoint
        public var progress: Double
    }

    let clicks: [EventLog.Click]

    public init(_ clicks: [EventLog.Click]) {
        self.clicks = clicks.sorted { $0.t < $1.t }
    }

    public func marks(at t: Double) -> [Mark] {
        clicks.filter { $0.t <= t && t < $0.t + Self.length }
            .map { Mark(position: CGPoint(x: $0.x, y: $0.y), progress: (t - $0.t) / Self.length) }
    }
}
