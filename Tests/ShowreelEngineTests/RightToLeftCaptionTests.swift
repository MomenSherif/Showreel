import CoreImage
import Testing
@testable import ShowreelEngine
import ShowreelKit

/// S-054: Arabic and mixed Arabic and English captions read right to left,
/// with English words in reading order, and the spoken word lit where it is.
@Suite("Right-to-left captions")
struct RightToLeftCaptionTests {
    static let size = CGSize(width: 640, height: 400)
    static let arabic = ["أهلاً", "بيكم،", "النهارده", "هنفتح"]
    /// Starts with English, still an Arabic line.
    static let mixed = ["API", "key", "هنفتح", "الـ", "dashboard", "وبعدين"]

    static func track(_ words: [String]) -> CaptionTrack {
        CaptionTrack(captions: [Caption(words: words.enumerated().map { i, w in
            CaptionWord(text: w, start: 1 + Double(i) * 0.4, end: 1.35 + Double(i) * 0.4)
        })], language: "ar")
    }

    static func frame(_ words: [String], word: Int) -> Bitmap {
        var style = Style()
        style.background = .gradient("graphite")
        return Bitmap(Renderer.frame(screen: RendererTests.screen, camera: nil, at: 1.2 + Double(word) * 0.4,
                                     scene: RendererTests.scene, style: RenderStyle(style: style, captions: track(words)), size: size))
    }

    /// The middle of the highlight pill: the pixels in the highlight color.
    static func pillCenter(_ frame: Bitmap) -> Double? {
        let c = CaptionStyle().highlightColor
        let target = (r: Int(c.r * 255), g: Int(c.g * 255), b: Int(c.b * 255))
        var xs: [Int] = []
        for y in 250..<400 { for x in 0..<640 {
            let p = frame.pixel(x: x, y: y)
            if abs(p.r - target.r) < 12 && abs(p.g - target.g) < 12 && abs(p.b - target.b) < 12 { xs.append(x) }
        } }
        guard xs.count > 20 else { return nil }
        return Double(xs.min()! + xs.max()!) / 2
    }

    @Test func directionFollowsTheLetters() {
        #expect(TextDirection.isRightToLeft(Self.arabic.joined(separator: " ")))
        let mixed = Self.mixed.joined(separator: " ")
        #expect(TextDirection.isRightToLeft(mixed), "three words each way: a tie reads from the right")
        #expect(TextDirection.isRightToLeft(mixed, language: "ar"))
        #expect(TextDirection.isRightToLeft("Open the API key page الآن", language: "ar"), "an Arabic track reads from the right")
        #expect(!TextDirection.isRightToLeft("Open the API key page الآن"), "mostly English with no language reads from the left")
        #expect(!TextDirection.isRightToLeft("Click Create Workspace to start.", language: "ar"))
        #expect(!TextDirection.isRightToLeft("Use the API key 123"))
    }

    /// The first spoken Arabic word is on the right, the last on the left.
    @Test func arabicReadsFromTheRight() throws {
        let centers = try (0..<Self.arabic.count).map { try #require(Self.pillCenter(Self.frame(Self.arabic, word: $0)), "word \($0)") }
        #expect(zip(centers, centers.dropFirst()).allSatisfy { $0 > $1 }, "\(centers)")
        #expect(centers[0] > 320 && centers[3] < 320, "\(centers)")
        try Self.frame(Self.arabic, word: 1).expectMatches(golden: "captions-arabic")
    }

    /// In a mixed line the Arabic order runs right to left, and "API key"
    /// keeps its own left-to-right order at the line's right end.
    @Test func mixedLineKeepsEnglishInOrder() throws {
        let centers = try (0..<Self.mixed.count).map { try #require(Self.pillCenter(Self.frame(Self.mixed, word: $0)), "word \($0)") }
        // "API" then "key" left to right, both at the right end, where the line starts.
        #expect(centers[0] < centers[1], "API key in English order: \(centers)")
        #expect(centers[1] > centers[2] && centers[0] > centers[2], "the line starts on the right: \(centers)")
        // Then the Arabic words, and "dashboard" in its place among them.
        #expect(centers[2] > centers[3] && centers[3] > centers[4] && centers[4] > centers[5], "\(centers)")
        try Self.frame(Self.mixed, word: 4).expectMatches(golden: "captions-mixed")
    }

    /// Lines break between words by characters, so Arabic marks stay with their letters.
    @Test func linesCountLettersWithTheirMarks() {
        let word = "مُحَمَّدٌ" // 4 letters, 9 scalars
        #expect(word.count == 4 && word.unicodeScalars.count == 9)
        let words = (0..<10).map { CaptionWord(text: word, start: Double($0), end: Double($0) + 0.5) }
        let lines = CaptionTrack.lines(from: words, maxCharacters: 14)
        // Three 4-letter words and two spaces make 14.
        #expect(lines.map(\.words.count) == [3, 3, 3, 1])
        #expect(lines.allSatisfy { $0.text.split(separator: " ").allSatisfy { $0 == word } })
    }
}
