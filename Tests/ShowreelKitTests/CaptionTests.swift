import Foundation
import Testing
@testable import ShowreelKit

@Suite("Captions")
struct CaptionTests {
    /// Words a quarter second apart, with no pauses.
    private func words(_ text: String, from start: Double = 0) -> [CaptionWord] {
        text.split(separator: " ").enumerated().map { i, word in
            CaptionWord(text: " " + word, start: start + Double(i) * 0.25, end: start + Double(i) * 0.25 + 0.2)
        }
    }

    /// S-039: lines are at most 42 characters, and no word is lost.
    @Test func linesStayWithinTheLimit() {
        let text = "click the record button to start a new recording then open it in the editor and pick a background you like for the video"
        let lines = CaptionTrack.lines(from: words(text))
        #expect(lines.count > 1)
        #expect(lines.allSatisfy { $0.text.count <= CaptionTrack.maxCharacters })
        #expect(lines.map(\.text).joined(separator: " ") == text)
    }

    @Test func linesKeepTheirWordsTimes() {
        let lines = CaptionTrack.lines(from: words("one two three", from: 2))
        #expect(lines.count == 1)
        #expect(lines[0].start == 2)
        #expect(abs(lines[0].end - 2.7) < 0.0001)
        #expect(lines[0].words.map(\.text) == ["one", "two", "three"])
    }

    @Test func aSentenceEndsALine() {
        let lines = CaptionTrack.lines(from: words("Welcome to Showreel. Click record."))
        #expect(lines.map(\.text) == ["Welcome to Showreel.", "Click record."])
    }

    @Test func aPauseEndsALine() {
        let lines = CaptionTrack.lines(from: words("first part") + words("second part", from: 3))
        #expect(lines.map(\.text) == ["first part", "second part"])
    }

    @Test func aLongWordGetsItsOwnLine() {
        let long = String(repeating: "a", count: 50)
        let lines = CaptionTrack.lines(from: words("hi \(long) there"))
        #expect(lines.map(\.text) == ["hi", long, "there"])
    }

    @Test func emptyWordsAreSkipped() {
        let lines = CaptionTrack.lines(from: [CaptionWord(text: "  ", start: 0, end: 0.1)] + words("hello"))
        #expect(lines.map(\.text) == ["hello"])
        #expect(CaptionTrack.lines(from: []).isEmpty)
    }

    @Test func aTrackRoundTripsThroughJSON() {
        let track = CaptionTrack(captions: CaptionTrack.lines(from: words("hello there. general")), language: "en_US")
        #expect(CaptionTrack.decode(track.encoded()) == track)
        #expect(CaptionTrack.decode(nil) == nil)
    }

    /// S-040: fixing a word keeps every word's time.
    @Test func editedTextKeepsWordTimes() throws {
        let caption = Caption(words: words("click the recrod button"))
        let fixed = try #require(caption.withText("click the record  button"))
        #expect(fixed.text == "click the record button")
        #expect(fixed.words.map(\.start) == caption.words.map(\.start))
        #expect(fixed.start == caption.start && fixed.end == caption.end)
    }

    @Test func editedTextWithMoreWordsSharesTheTime() throws {
        let caption = Caption(words: words("hello there"))
        let fixed = try #require(caption.withText("hello over there"))
        #expect(fixed.words.count == 3)
        #expect(fixed.words.first?.start == caption.start)
        #expect(abs((fixed.words.last?.end ?? 0) - caption.end) < 0.0001)
        #expect(caption.withText("   ") == nil)
    }

    private func track() -> CaptionTrack {
        CaptionTrack(captions: [Caption(words: words("one two", from: 1)), Caption(words: words("three four", from: 4))])
    }

    @Test func resizingStopsAtTheNeighbor() {
        let t = track(), first = t.captions[0], second = t.captions[1]
        let longer = t.resizing(first.id, edge: .end, by: 10, duration: 20)
        #expect(longer.captions[0].end == second.start)
        let shorter = t.resizing(first.id, edge: .end, by: -10, duration: 20)
        #expect(abs(shorter.captions[0].length - CaptionTrack.minLength) < 0.0001)
        let earlier = t.resizing(first.id, edge: .start, by: -5, duration: 20)
        #expect(earlier.captions[0].start == 0)
        // Words stretch with the caption.
        #expect(earlier.captions[0].words.first?.start == 0)
        #expect(abs((earlier.captions[0].words.last?.end ?? 0) - first.end) < 0.0001)
    }

    @Test func movingStopsAtTheNeighborAndKeepsLength() {
        let t = track(), first = t.captions[0], second = t.captions[1]
        let moved = t.moving(first.id, by: 10, duration: 20)
        #expect(abs(moved.captions[0].end - second.start) < 0.0001)
        #expect(abs(moved.captions[0].length - first.length) < 0.0001)
        let last = t.moving(second.id, by: 100, duration: 20)
        #expect(abs(last.captions[1].end - 20) < 0.0001)
    }

    @Test func changingToNilRemovesTheCaption() {
        let t = track()
        #expect(t.changing(t.captions[0].id) { _ in nil }.captions.map(\.id) == [t.captions[1].id])
    }

    /// S-041: the caption and word on screen at a moment.
    @Test func captionAndWordAtATime() {
        let t = track()
        #expect(t.caption(at: 0.5) == nil)
        #expect(t.caption(at: 1.1)?.id == t.captions[0].id)
        #expect(t.caption(at: 3) == nil)
        #expect(t.caption(at: 4.3)?.id == t.captions[1].id)
        let caption = t.captions[0]
        #expect(caption.wordIndex(at: 1.0) == 0)
        #expect(caption.wordIndex(at: 1.22) == 0)  // between words: the last one holds
        #expect(caption.wordIndex(at: 1.3) == 1)
        #expect(caption.wordIndex(at: 0.9) == nil)
    }

    @Test func styleWithoutCaptionFieldsDecodesWithDefaults() throws {
        let old = Data(#"{"padding":0.1}"#.utf8)
        let style = try JSONDecoder().decode(Style.self, from: old)
        #expect(style.captions == CaptionStyle())
        var changed = Style()
        changed.captions.position = .top
        changed.captions.size = 1.4
        #expect(Style.decode(changed.encoded()).captions == changed.captions)
        #expect(changed.asPreset.captions == changed.captions)
    }
}
