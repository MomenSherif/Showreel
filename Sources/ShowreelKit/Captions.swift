import Foundation

/// One spoken word and when it was said, in source time.
public struct CaptionWord: Codable, Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// One line of captions (docs/GLOSSARY.md, "Caption"), shown from `start`
/// to `end`. Times are source time, like zooms, so a cut shifts them for free.
/// The words keep their own timing for the spoken-word highlight (S-041).
public struct Caption: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String
    public var words: [CaptionWord]

    public init(id: UUID = UUID(), words: [CaptionWord]) {
        self.id = id
        self.words = words
        start = words.first?.start ?? 0
        end = words.last?.end ?? 0
        text = words.map(\.text).joined(separator: " ")
    }

    public var length: Double { end - start }

    /// The caption with new text (S-040). When the word count is the same,
    /// each word keeps its time; otherwise the words share the caption's time
    /// evenly. Nil for empty text.
    public func withText(_ newText: String) -> Caption? {
        let parts = newText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return nil }
        var copy = self
        if parts.count == words.count {
            copy.words = zip(words, parts).map { CaptionWord(text: $1, start: $0.start, end: $0.end) }
        } else {
            let step = length / Double(parts.count)
            copy.words = parts.enumerated().map { i, part in
                CaptionWord(text: part, start: start + Double(i) * step, end: start + Double(i + 1) * step)
            }
        }
        copy.text = parts.joined(separator: " ")
        return copy
    }

    /// The caption shown from `newStart` to `newEnd`, its words stretched to fit.
    public func retimed(start newStart: Double, end newEnd: Double) -> Caption {
        var copy = self
        let ratio = length > 0 ? (newEnd - newStart) / length : 0
        copy.words = words.map { word in
            CaptionWord(text: word.text, start: newStart + (word.start - start) * ratio, end: newStart + (word.end - start) * ratio)
        }
        copy.start = newStart
        copy.end = newEnd
        return copy
    }
}

/// Every caption of a project, in order. Stored as JSON in `Project.captionsData`.
public struct CaptionTrack: Codable, Equatable, Sendable {
    public var captions: [Caption]
    /// The language they were made in, as a locale identifier ("en_US").
    public var language: String

    public init(captions: [Caption] = [], language: String = "") {
        self.captions = captions.sorted { $0.start < $1.start }
        self.language = language
    }

    /// The longest line, in characters: the usual limit for one caption line.
    public static let maxCharacters = 42
    /// A silence this long, in seconds, starts a new line.
    public static let pauseBreak = 0.8

    /// Groups words into lines of up to `maxCharacters` (S-039). A line also
    /// ends after a sentence and at a pause. A single word longer than the
    /// limit gets a line of its own.
    public static func lines(from words: [CaptionWord], maxCharacters: Int = maxCharacters) -> [Caption] {
        var lines: [Caption] = []
        var line: [CaptionWord] = []
        var count = 0
        for word in words {
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let clean = CaptionWord(text: text, start: word.start, end: max(word.end, word.start))
            if let last = line.last, count + 1 + text.count > maxCharacters || clean.start - last.end >= pauseBreak {
                lines.append(Caption(words: line))
                line = []
                count = 0
            }
            count += line.isEmpty ? text.count : 1 + text.count
            line.append(clean)
            if endsSentence(text) {
                lines.append(Caption(words: line))
                line = []
                count = 0
            }
        }
        if !line.isEmpty { lines.append(Caption(words: line)) }
        return lines
    }

    private static func endsSentence(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        return ".?!…".contains(last)
    }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// Nil when there is no data (captions were never made).
    public static func decode(_ data: Data?) -> CaptionTrack? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(CaptionTrack.self, from: data)
    }
}

/// Changing a caption by hand (S-040). Captions never overlap: a drag stops
/// at the neighbor's edge and at the ends of the recording.
extension CaptionTrack {
    /// The shortest caption a drag can leave.
    public static let minLength = 0.3

    public enum Edge: Sendable { case start, end }

    /// The captions with the caption `id` replaced by `change(caption)`, or
    /// removed when `change` returns nil.
    public func changing(_ id: Caption.ID, _ change: (Caption) -> Caption?) -> CaptionTrack {
        guard let i = captions.firstIndex(where: { $0.id == id }) else { return self }
        var copy = self
        if let new = change(captions[i]) { copy.captions[i] = new } else { copy.captions.remove(at: i) }
        return copy
    }

    /// The caption `id` moved by `delta` seconds, stopped by its neighbors.
    public func moving(_ id: Caption.ID, by delta: Double, duration: Double) -> CaptionTrack {
        guard let i = captions.firstIndex(where: { $0.id == id }) else { return self }
        let caption = captions[i]
        let lo = i > 0 ? captions[i - 1].end : 0
        let hi = i + 1 < captions.count ? captions[i + 1].start : duration
        let start = min(max(caption.start + delta, lo), max(lo, hi - caption.length))
        var copy = self
        copy.captions[i] = caption.retimed(start: start, end: start + caption.length)
        return copy
    }

    /// The caption `id` with one edge moved by `delta` seconds, stopped by
    /// its neighbors and never shorter than `minLength`.
    public func resizing(_ id: Caption.ID, edge: Edge, by delta: Double, duration: Double) -> CaptionTrack {
        guard let i = captions.firstIndex(where: { $0.id == id }) else { return self }
        let caption = captions[i]
        var copy = self
        switch edge {
        case .start:
            let lo = i > 0 ? captions[i - 1].end : 0
            let start = min(max(caption.start + delta, lo), caption.end - Self.minLength)
            copy.captions[i] = caption.retimed(start: start, end: caption.end)
        case .end:
            let hi = i + 1 < captions.count ? captions[i + 1].start : duration
            let end = max(min(caption.end + delta, hi), caption.start + Self.minLength)
            copy.captions[i] = caption.retimed(start: caption.start, end: end)
        }
        return copy
    }
}
