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
}
