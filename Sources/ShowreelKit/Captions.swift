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
