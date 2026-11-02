import CoreGraphics
import Foundation

/// A timed zoom-in on part of the recording (docs/GLOSSARY.md, "Zoom").
/// Times are source time, like the cut, so a cut shifts zooms for free.
public struct ZoomSegment: Codable, Equatable, Identifiable, Sendable {
    /// Where the zoom looks (S-031).
    public enum Focus: String, Codable, CaseIterable, Sendable {
        /// The spot the clicks or typing happened.
        case auto
        /// The cursor, moving with it.
        case followCursor
        /// A point set by hand.
        case fixed
    }

    public var id: UUID
    public var start: Double
    public var end: Double
    /// 1...4; 2 by default.
    public var scale: Double
    /// The spot to zoom on, normalized to the recording (top-left origin).
    public var x: Double
    public var y: Double
    public var focus: Focus

    public init(id: UUID = UUID(), start: Double, end: Double, scale: Double = 2,
                x: Double = 0.5, y: Double = 0.5, focus: Focus = .auto) {
        self.id = id
        self.start = start
        self.end = end
        self.scale = scale
        self.x = x
        self.y = y
        self.focus = focus
    }

    public var length: Double { end - start }

    /// Where the zoom looks at `t`: its spot, or for Follow Cursor the
    /// smoothed cursor (its spot when no cursor was recorded).
    public func spot(at t: Double, cursor: CursorPath) -> CGPoint {
        if focus == .followCursor, let p = cursor.smoothed(at: t) { return p }
        return CGPoint(x: x, y: y)
    }

    public static let scaleRange: ClosedRange<Double> = 1...4
}

/// What the zoom shows at one moment.
public struct ZoomView: Equatable, Sendable {
    /// 1 when not zoomed.
    public var scale: Double
    /// The part of the recording on screen, normalized, top-left origin.
    /// Always inside the unit square.
    public var rect: CGRect

    public static let none = ZoomView(scale: 1, rect: CGRect(x: 0, y: 0, width: 1, height: 1))

    public var isZoomed: Bool { scale > 1.0001 }
}

/// Every zoom of a project, in order and never overlapping. Stored as JSON
/// in `Project.zoomsData`.
public struct ZoomTrack: Codable, Equatable, Sendable {
    public var segments: [ZoomSegment]

    public init(segments: [ZoomSegment] = []) {
        self.segments = segments.sorted { $0.start < $1.start }
    }

    /// Seconds it takes to ease in and out of a zoom.
    public static let easeTime = 0.5

    /// The zoom at source time `t`: it eases in from the segment's start
    /// and out toward its end (S-033 replaces this with a spring). Spots are
    /// normalized to the whole recording; `crop` maps them onto the part
    /// that shows. Follow Cursor looks at `cursor`, smoothed.
    public func view(at t: Double, cursor: CursorPath = CursorPath(), crop: CropRect = .full) -> ZoomView {
        guard let segment = segment(at: t) else { return .none }
        let ramp = min(Self.easeTime, segment.length / 3)
        let progress = ramp > 0 ? min((t - segment.start) / ramp, (segment.end - t) / ramp, 1) : 1
        let eased = progress * progress * (3 - 2 * progress)
        let scale = 1 + (min(max(segment.scale, 1), 4) - 1) * eased
        let spot = crop.mapClamped(segment.spot(at: t, cursor: cursor))
        return Self.view(scale: scale, x: spot.x, y: spot.y)
    }

    /// The segment that covers `t`.
    public func segment(at t: Double) -> ZoomSegment? {
        segments.first { $0.start <= t && t <= $0.end }
    }

    /// The window of the recording `scale` times bigger, centered on (x, y)
    /// but kept inside the recording.
    public static func view(scale: Double, x: Double, y: Double) -> ZoomView {
        guard scale > 1.0001 else { return .none }
        let size = 1 / scale
        let left = min(max(x - size / 2, 0), 1 - size)
        let top = min(max(y - size / 2, 0), 1 - size)
        return ZoomView(scale: scale, rect: CGRect(x: left, y: top, width: size, height: size))
    }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// Nil when there is no data yet (zooms were never made).
    public static func decode(_ data: Data?) -> ZoomTrack? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(ZoomTrack.self, from: data)
    }
}

/// Adding, moving, and resizing by hand (S-032). Zooms never overlap: a
/// drag stops at the neighbor's edge and at the ends of the recording.
extension ZoomTrack {
    /// The shortest zoom a drag can leave.
    public static let minLength = 0.5
    /// A zoom added by hand.
    public static let newLength = 2.0

    public enum Edge: Sendable { case start, end }

    /// Room around source time `t`: from the end of the zoom before to the
    /// start of the zoom after. Nil when `t` is inside a zoom.
    public func gap(around t: Double, duration: Double) -> ClosedRange<Double>? {
        guard segment(at: t) == nil else { return nil }
        let before = segments.last { $0.end <= t }?.end ?? 0
        let after = segments.first { $0.start >= t }?.start ?? duration
        return before <= after ? before...after : nil
    }

    /// Adds a zoom starting at `t` (or earlier, when it would not fit before
    /// the next one) and returns it. Nil when there is no room for one.
    public mutating func add(at t: Double, duration: Double, x: Double = 0.5, y: Double = 0.5) -> ZoomSegment? {
        guard let gap = gap(around: t, duration: duration), gap.upperBound - gap.lowerBound >= Self.minLength else { return nil }
        let length = min(Self.newLength, gap.upperBound - gap.lowerBound)
        let start = min(max(t, gap.lowerBound), gap.upperBound - length)
        let zoom = ZoomSegment(start: start, end: start + length, x: x, y: y, focus: .auto)
        self = ZoomTrack(segments: segments + [zoom])
        return zoom
    }

    /// The zoom `id` moved by `delta` seconds, stopped by its neighbors.
    public func moving(_ id: ZoomSegment.ID, by delta: Double, duration: Double) -> ZoomTrack {
        guard let i = segments.firstIndex(where: { $0.id == id }) else { return self }
        let zoom = segments[i]
        let lo = i > 0 ? segments[i - 1].end : 0
        let hi = i + 1 < segments.count ? segments[i + 1].start : duration
        let start = min(max(zoom.start + delta, lo), max(lo, hi - zoom.length))
        var copy = self
        copy.segments[i].start = start
        copy.segments[i].end = start + zoom.length
        return copy
    }

    /// The zoom `id` with one edge moved by `delta` seconds, stopped by its
    /// neighbors and never shorter than `minLength`.
    public func resizing(_ id: ZoomSegment.ID, edge: Edge, by delta: Double, duration: Double) -> ZoomTrack {
        guard let i = segments.firstIndex(where: { $0.id == id }) else { return self }
        var copy = self
        let zoom = segments[i]
        switch edge {
        case .start:
            let lo = i > 0 ? segments[i - 1].end : 0
            copy.segments[i].start = min(max(zoom.start + delta, lo), zoom.end - Self.minLength)
        case .end:
            let hi = i + 1 < segments.count ? segments[i + 1].start : duration
            copy.segments[i].end = max(min(zoom.end + delta, hi), zoom.start + Self.minLength)
        }
        return copy
    }
}

/// Makes zooms from what happened during a recording (S-030): one where the
/// person clicked, and one where they typed.
public enum AutoZoom {
    public struct Rules: Sendable {
        /// Clicks closer in time than this can share a zoom…
        public var clickGap = 2.5
        /// …when they are within this share of the screen of each other.
        public var reach = 0.3
        public var minLength = 1.5
        public var scale = 2.0
        /// The zoom starts this long before the first event, so it has
        /// arrived by the time the click happens.
        public var lead = 0.6
        /// And stays this long after the last one.
        public var hold = 1.6
        /// Key presses closer than this belong to one typing burst…
        public var keyGap = 1.2
        /// …of at least this many keys.
        public var minKeys = 4

        public init() {}
    }

    /// The zooms for a recording `duration` seconds long. Empty when it is
    /// shorter than one zoom.
    public static func segments(from log: EventLog, duration: Double, rules: Rules = Rules()) -> [ZoomSegment] {
        guard duration >= rules.minLength else { return [] }
        let candidates = (clickGroups(log, rules) + typingBursts(log, rules)).sorted { $0.start < $1.start }
        var placed: [Candidate] = []
        for var next in candidates {
            if var last = placed.last, next.start < last.end {
                if last.isNear(next, reach: rules.reach) {
                    placed[placed.count - 1] = last.merged(with: next)
                    continue
                }
                // Somewhere else: the earlier zoom hands over to this one.
                last.end = max(last.start + rules.minLength, next.start)
                placed[placed.count - 1] = last
                next.start = last.end
            }
            next.end = max(next.end, next.start + rules.minLength)
            placed.append(next)
        }
        // Keep everything inside the recording, still at least minLength long.
        var result: [ZoomSegment] = []
        for candidate in placed {
            let floor = result.last?.end ?? 0
            var start = max(candidate.start, floor)
            let end = min(max(candidate.end, start + rules.minLength), duration)
            if end - start < rules.minLength { start = max(floor, end - rules.minLength) }
            guard end - start >= rules.minLength - 1e-9 else { continue }
            result.append(ZoomSegment(start: start, end: end, scale: rules.scale,
                                      x: candidate.x, y: candidate.y, focus: .auto))
        }
        return result
    }

    struct Candidate {
        var start: Double
        var end: Double
        var x: Double
        var y: Double
        /// How many events the spot is the average of.
        var weight: Double

        func isNear(_ other: Candidate, reach: Double) -> Bool {
            abs(other.x - x) <= reach && abs(other.y - y) <= reach
        }

        func merged(with other: Candidate) -> Candidate {
            let w = weight + other.weight
            return Candidate(start: min(start, other.start), end: max(end, other.end),
                             x: (x * weight + other.x * other.weight) / w,
                             y: (y * weight + other.y * other.weight) / w, weight: w)
        }
    }

    /// Clicks less than `clickGap` apart and within `reach` of the group's
    /// center become one zoom.
    static func clickGroups(_ log: EventLog, _ rules: Rules) -> [Candidate] {
        var groups: [(first: Double, last: Double, x: Double, y: Double, n: Double)] = []
        for click in log.clicks.sorted(by: { $0.t < $1.t }) {
            if let g = groups.last, click.t - g.last < rules.clickGap,
               abs(click.x - g.x) <= rules.reach, abs(click.y - g.y) <= rules.reach {
                let n = g.n + 1
                groups[groups.count - 1] = (g.first, click.t, (g.x * g.n + click.x) / n, (g.y * g.n + click.y) / n, n)
            } else {
                groups.append((click.t, click.t, click.x, click.y, 1))
            }
        }
        return groups.map {
            Candidate(start: max(0, $0.first - rules.lead), end: $0.last + rules.hold, x: $0.x, y: $0.y, weight: $0.n)
        }
    }

    /// Runs of at least `minKeys` key presses, each less than `keyGap` after
    /// the one before, zoom on the caret. Without a logged caret they use the
    /// last click before the burst, then the cursor.
    static func typingBursts(_ log: EventLog, _ rules: Rules) -> [Candidate] {
        var bursts: [(start: Double, end: Double, n: Int)] = []
        for key in log.keys.sorted(by: { $0.t < $1.t }) {
            if let b = bursts.last, key.t - b.end < rules.keyGap {
                bursts[bursts.count - 1] = (b.start, key.t, b.n + 1)
            } else {
                bursts.append((key.t, key.t, 1))
            }
        }
        return bursts.filter { $0.n >= rules.minKeys }.compactMap { burst in
            guard let spot = spot(typingFrom: burst.start, to: burst.end, in: log) else { return nil }
            return Candidate(start: max(0, burst.start - rules.lead), end: burst.end + rules.hold,
                             x: spot.x, y: spot.y, weight: 1)
        }
    }

    static func spot(typingFrom start: Double, to end: Double, in log: EventLog) -> CGPoint? {
        let carets = log.caret.filter { $0.t >= start - 0.5 && $0.t <= end }
        if !carets.isEmpty {
            let n = Double(carets.count)
            return CGPoint(x: carets.map(\.x).reduce(0, +) / n, y: carets.map(\.y).reduce(0, +) / n)
        }
        if let click = log.clicks.last(where: { $0.t <= start && start - $0.t < 30 }) {
            return CGPoint(x: click.x, y: click.y)
        }
        if let cursor = log.cursor.last(where: { $0.t <= start }) ?? log.cursor.first {
            return CGPoint(x: cursor.x, y: cursor.y)
        }
        return nil
    }
}

extension EditList {
    /// Where the source range `start...end` shows in the edited video: one
    /// range per kept segment it overlaps, in edit time.
    public func editRanges(fromSource start: Double, to end: Double) -> [ClosedRange<Double>] {
        var at = 0.0
        var ranges: [ClosedRange<Double>] = []
        for segment in segments {
            let lo = max(start, segment.start), hi = min(end, segment.end)
            if hi > lo { ranges.append((at + lo - segment.start)...(at + hi - segment.start)) }
            at += segment.length
        }
        return ranges
    }
}
