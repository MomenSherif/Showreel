import CoreGraphics
import Foundation

/// A timed rectangle that hides part of the screen (docs/GLOSSARY.md,
/// "Blur"). Times are source time, like zooms, so a cut shifts it for free.
/// The rectangle is normalized to the whole recording (top-left origin), so
/// it stays on the same content when a zoom, crop, padding, or device frame
/// moves the screen (S-048).
public struct BlurRegion: Codable, Equatable, Identifiable, Sendable {
    /// How the area is hidden (S-049).
    public enum Style: String, Codable, CaseIterable, Sendable {
        case blur, pixelate
    }

    public var id: UUID
    public var start: Double
    public var end: Double
    /// The hidden area, normalized to the recording, top-left origin.
    public var rect: CropRect
    public var style: Style
    /// 0...1: how strong the blur or how big the blocks.
    public var strength: Double

    public init(id: UUID = UUID(), start: Double, end: Double, rect: CropRect = BlurRegion.defaultRect,
                style: Style = .blur, strength: Double = 0.6) {
        self.id = id
        self.start = start
        self.end = end
        self.rect = rect
        self.style = style
        self.strength = strength
    }

    public var length: Double { end - start }

    /// A new blur's rectangle: a band in the middle, ready to be dragged.
    public static let defaultRect = CropRect(x: 0.35, y: 0.42, width: 0.3, height: 0.16) // grid: ok normalized
    /// The smallest side, as a share of the recording, so it stays grabbable.
    public static let minSide = 0.02

    /// The rectangle in pixels of a `source`-sized recording, Core Image's
    /// bottom-left origin, on whole pixels, inside the recording.
    public func pixelRect(in source: CGRect) -> CGRect {
        let top = rect.pixels(of: source.size)
        return CGRect(x: source.minX + top.minX, y: source.minY + source.height - top.maxY,
                      width: top.width, height: top.height).intersection(source)
    }

    /// Gaussian blur radius in pixels of a recording whose long side is `long`.
    public func blurSigma(long: Double) -> Double { (0.004 + 0.016 * min(max(strength, 0), 1)) * long }
    /// Pixelate block size in pixels of a recording whose long side is `long`.
    public func blockSize(long: Double) -> Double { max(2, (0.006 + 0.024 * min(max(strength, 0), 1)) * long) }
}

/// Every blur of a project, in order and never overlapping, like zooms.
/// Stored as JSON in `Project.blursData`.
public struct BlurTrack: Codable, Equatable, Sendable {
    public var regions: [BlurRegion]

    public init(regions: [BlurRegion] = []) {
        self.regions = regions.sorted { $0.start < $1.start }
    }

    /// A blur added by hand lasts this long (S-048).
    public static let newLength = 3.0
    /// The shortest blur a drag can leave.
    public static let minLength = 0.25

    /// The blur on screen at source time `t`.
    public func region(at t: Double) -> BlurRegion? {
        regions.first { $0.start <= t && t < $0.end }
    }

    /// Adds a blur starting at `t` (earlier when it would not fit before the
    /// next one) and returns it. Nil when there is no room.
    public mutating func add(at t: Double, duration: Double, rect: CropRect = BlurRegion.defaultRect) -> BlurRegion? {
        guard let span = Spans.added(at: t, length: Self.newLength, minLength: Self.minLength,
                                     in: regions.map { $0.start...$0.end }, duration: duration) else { return nil }
        let blur = BlurRegion(start: span.lowerBound, end: span.upperBound, rect: rect)
        self = BlurTrack(regions: regions + [blur])
        return blur
    }

    /// The blur `id` moved by `delta` seconds, stopped by its neighbors.
    public func moving(_ id: BlurRegion.ID, by delta: Double, duration: Double) -> BlurTrack {
        guard let i = regions.firstIndex(where: { $0.id == id }) else { return self }
        let span = Spans.moving(i, by: delta, in: regions.map { $0.start...$0.end }, duration: duration)
        var copy = self
        copy.regions[i].start = span.lowerBound
        copy.regions[i].end = span.upperBound
        return copy
    }

    /// The blur `id` with one edge moved by `delta` seconds.
    public func resizing(_ id: BlurRegion.ID, edge: Spans.Edge, by delta: Double, duration: Double) -> BlurTrack {
        guard let i = regions.firstIndex(where: { $0.id == id }) else { return self }
        let span = Spans.resizing(i, edge: edge, by: delta, minLength: Self.minLength,
                                  in: regions.map { $0.start...$0.end }, duration: duration)
        var copy = self
        copy.regions[i].start = span.lowerBound
        copy.regions[i].end = span.upperBound
        return copy
    }

    /// The blur `id` with its rectangle changed by `change`.
    public func changing(_ id: BlurRegion.ID, _ change: (inout BlurRegion) -> Void) -> BlurTrack {
        var copy = self
        if let i = copy.regions.firstIndex(where: { $0.id == id }) { change(&copy.regions[i]) }
        return copy
    }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// An empty track when there is no data yet.
    public static func decode(_ data: Data?) -> BlurTrack {
        guard let data, !data.isEmpty, let track = try? JSONDecoder().decode(BlurTrack.self, from: data) else { return BlurTrack() }
        return track
    }
}

/// The timing rules every timeline lane of non-overlapping blocks shares
/// (zooms, blurs): a block never overlaps a neighbor and stays inside the
/// recording. `spans` are in order.
public enum Spans {
    public enum Edge: Sendable { case start, end }

    /// Room around `t`: from the end of the span before to the start of the
    /// one after. Nil when `t` is inside a span.
    public static func gap(around t: Double, in spans: [ClosedRange<Double>], duration: Double) -> ClosedRange<Double>? {
        guard !spans.contains(where: { $0.lowerBound <= t && t < $0.upperBound }) else { return nil }
        let before = spans.last { $0.upperBound <= t }?.upperBound ?? 0
        let after = spans.first { $0.lowerBound >= t }?.lowerBound ?? duration
        return before <= after ? before...after : nil
    }

    /// A new span of up to `length` starting at `t`, or earlier when it would
    /// not fit. Nil when the gap is shorter than `minLength`.
    public static func added(at t: Double, length: Double, minLength: Double,
                             in spans: [ClosedRange<Double>], duration: Double) -> ClosedRange<Double>? {
        guard let gap = gap(around: t, in: spans, duration: duration),
              gap.upperBound - gap.lowerBound >= minLength else { return nil }
        let length = min(length, gap.upperBound - gap.lowerBound)
        let start = min(max(t, gap.lowerBound), gap.upperBound - length)
        return start...(start + length)
    }

    /// Span `i` moved by `delta`, stopped by its neighbors.
    public static func moving(_ i: Int, by delta: Double, in spans: [ClosedRange<Double>], duration: Double) -> ClosedRange<Double> {
        let span = spans[i], length = span.upperBound - span.lowerBound
        let lo = i > 0 ? spans[i - 1].upperBound : 0
        let hi = i + 1 < spans.count ? spans[i + 1].lowerBound : duration
        let start = min(max(span.lowerBound + delta, lo), max(lo, hi - length))
        return start...(start + length)
    }

    /// Span `i` with one edge moved by `delta`, stopped by its neighbors and
    /// never shorter than `minLength`.
    public static func resizing(_ i: Int, edge: Edge, by delta: Double, minLength: Double,
                                in spans: [ClosedRange<Double>], duration: Double) -> ClosedRange<Double> {
        let span = spans[i]
        switch edge {
        case .start:
            let lo = i > 0 ? spans[i - 1].upperBound : 0
            return min(max(span.lowerBound + delta, lo), span.upperBound - minLength)...span.upperBound
        case .end:
            let hi = i + 1 < spans.count ? spans[i + 1].lowerBound : duration
            return span.lowerBound...max(min(span.upperBound + delta, hi), span.lowerBound + minLength)
        }
    }
}

extension CropRect {
    /// The rectangle after dragging `handle` by `dx`, `dy`, kept inside the
    /// recording and at least `minSide` on each side (crops and blurs).
    public func dragging(_ handle: Handle, dx: Double, dy: Double, minSide: Double) -> CropRect {
        var left = x, top = y, right = x + width, bottom = y + height
        switch handle {
        case .move:
            return CropRect(x: min(max(x + dx, 0), 1 - width), y: min(max(y + dy, 0), 1 - height), width: width, height: height)
        case .topLeading: left += dx; top += dy
        case .top: top += dy
        case .topTrailing: right += dx; top += dy
        case .leading: left += dx
        case .trailing: right += dx
        case .bottomLeading: left += dx; bottom += dy
        case .bottom: bottom += dy
        case .bottomTrailing: right += dx; bottom += dy
        }
        left = min(max(left, 0), right - minSide)
        top = min(max(top, 0), bottom - minSide)
        right = max(min(right, 1), left + minSide)
        bottom = max(min(bottom, 1), top + minSide)
        return CropRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The rectangle spanning two points (a drag on the canvas), kept inside
    /// the recording and at least `minSide` on each side.
    public static func spanning(_ a: CGPoint, _ b: CGPoint, minSide: Double) -> CropRect {
        let left = min(max(min(a.x, b.x), 0), 1 - minSide), top = min(max(min(a.y, b.y), 0), 1 - minSide)
        let right = min(max(max(a.x, b.x), left + minSide), 1), bottom = min(max(max(a.y, b.y), top + minSide), 1)
        return CropRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
