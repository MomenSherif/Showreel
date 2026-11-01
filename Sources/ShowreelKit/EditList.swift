import Foundation

/// The cut of a recording: which parts of the source files play, in order
/// (S-018, S-019). Edits never touch the files; they change this list.
///
/// Two time scales: **source time** is a moment in the recorded files, and
/// **edit time** is a moment in the video after cuts. Zooms, captions, and
/// events are stored in source time, so deleting a section shifts everything
/// after it, and anything inside a deleted section simply stops showing.
public struct EditList: Codable, Equatable, Sendable {
    /// One kept part of the source, in source seconds.
    public struct Segment: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var start: Double
        public var end: Double

        public init(id: UUID = UUID(), start: Double, end: Double) {
            self.id = id
            self.start = start
            self.end = end
        }

        public var length: Double { end - start }
    }

    /// The shortest a segment can get, so it stays visible and grabbable.
    public static let minLength = 0.1

    /// Kept segments in source order. They never overlap.
    public private(set) var segments: [Segment]
    /// Length of the source files.
    public private(set) var sourceDuration: Double

    /// The whole recording, uncut.
    public init(sourceDuration: Double) {
        self.sourceDuration = max(sourceDuration, 0)
        segments = [Segment(start: 0, end: self.sourceDuration)]
    }

    /// Length of the edited video.
    public var duration: Double { segments.reduce(0) { $0 + $1.length } }

    public var isUncut: Bool {
        segments.count == 1 && segments[0].start == 0 && segments[0].end == sourceDuration
    }

    /// Where `segment` starts in edit time.
    public func editStart(of id: Segment.ID) -> Double? {
        var t = 0.0
        for segment in segments {
            if segment.id == id { return t }
            t += segment.length
        }
        return nil
    }

    /// The segment playing at edit time `t`, and where it starts in edit time.
    /// At a cut, the later segment wins; at the very end, the last one.
    public func segment(atEditTime t: Double) -> (segment: Segment, editStart: Double)? {
        var start = 0.0
        for (i, segment) in segments.enumerated() {
            let end = start + segment.length
            if t < end || i == segments.count - 1 { return t >= start - 1e-9 ? (segment, start) : nil }
            start = end
        }
        return nil
    }

    /// The source moment shown at edit time `t`.
    public func sourceTime(atEditTime t: Double) -> Double? {
        guard let (segment, start) = segment(atEditTime: min(max(t, 0), duration)) else { return nil }
        return segment.start + (min(max(t, 0), duration) - start)
    }

    /// Where source moment `s` plays in the edit, or nil when it was cut out.
    public func editTime(atSourceTime s: Double) -> Double? {
        var start = 0.0
        for segment in segments {
            if s >= segment.start && s <= segment.end { return start + (s - segment.start) }
            start += segment.length
        }
        return nil
    }

    // MARK: Edits

    /// Moves a segment's start to source time `s`, kept inside the gap
    /// before it and at least `minLength` long. Returns the start it got.
    @discardableResult
    public mutating func trimStart(_ id: Segment.ID, toSource s: Double) -> Double? {
        guard let i = segments.firstIndex(where: { $0.id == id }) else { return nil }
        let floor = i > 0 ? segments[i - 1].end : 0
        segments[i].start = min(max(s, floor), segments[i].end - Self.minLength)
        return segments[i].start
    }

    /// Moves a segment's end to source time `s`, kept inside the gap after it.
    @discardableResult
    public mutating func trimEnd(_ id: Segment.ID, toSource s: Double) -> Double? {
        guard let i = segments.firstIndex(where: { $0.id == id }) else { return nil }
        let ceiling = i < segments.count - 1 ? segments[i + 1].start : sourceDuration
        segments[i].end = max(min(s, ceiling), segments[i].start + Self.minLength)
        return segments[i].end
    }

    /// Splits the segment under edit time `t` into two. Nothing happens
    /// within `minLength` of either end. Returns the new right-hand segment.
    @discardableResult
    public mutating func split(atEditTime t: Double) -> Segment? {
        guard let (segment, start) = segment(atEditTime: t),
              let i = segments.firstIndex(of: segment) else { return nil }
        let s = segment.start + (t - start)
        guard s - segment.start >= Self.minLength, segment.end - s >= Self.minLength else { return nil }
        let right = Segment(start: s, end: segment.end)
        segments[i].end = s
        segments.insert(right, at: i + 1)
        return right
    }

    /// Removes a segment; the ones after it move up to close the gap. The
    /// last segment cannot be deleted.
    @discardableResult
    public mutating func delete(_ id: Segment.ID) -> Bool {
        guard segments.count > 1, let i = segments.firstIndex(where: { $0.id == id }) else { return false }
        segments.remove(at: i)
        return true
    }

    // MARK: Storage

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// The stored list, or the uncut recording when there is none or it does
    /// not fit the files (they changed).
    public static func decode(_ data: Data?, sourceDuration: Double) -> EditList {
        guard let data, var list = try? JSONDecoder().decode(EditList.self, from: data),
              !list.segments.isEmpty else { return EditList(sourceDuration: sourceDuration) }
        // A list saved against a longer file is cut back to the file.
        list.sourceDuration = sourceDuration
        list.segments = list.segments.compactMap { segment in
            var s = segment
            s.end = min(s.end, sourceDuration)
            return s.length >= minLength ? s : nil
        }
        return list.segments.isEmpty ? EditList(sourceDuration: sourceDuration) : list
    }
}
