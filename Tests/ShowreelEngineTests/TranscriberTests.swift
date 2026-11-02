import Foundation
import Speech
import Testing
import ShowreelEngine
import ShowreelKit

@Suite("Transcriber")
struct TranscriberTests {
    /// Speech made with `say`, so the test needs no recording.
    private func speech(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("showreel-speech-\(UUID().uuidString).m4a")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Samantha", "-o", url.path, "--data-format=aac", text]
        try say.run()
        say.waitUntilExit()
        return url
    }

    /// S-039: SpeechAnalyzer gives each word its time, and the words group
    /// into caption lines of up to 42 characters.
    @Test(.enabled(if: SpeechTranscriber.isAvailable), .timeLimit(.minutes(5)))
    func wordsHaveTimesAndGroupIntoLines() async throws {
        let url = try speech("Welcome to Showreel. Click the record button to start a new recording, then open it in the editor.")
        defer { try? FileManager.default.removeItem(at: url) }
        let (words, _) = try await Transcriber.words(in: url, locale: Locale(identifier: "en_US")) { _ in }
        #expect(words.count >= 15)
        #expect(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start })
        #expect(words.allSatisfy { $0.end >= $0.start })
        let text = words.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ").lowercased()
        #expect(text.contains("record button"))
        let lines = CaptionTrack.lines(from: words)
        #expect(lines.count >= 3)
        #expect(lines.allSatisfy { $0.text.count <= CaptionTrack.maxCharacters })
        #expect(lines.first?.text.hasSuffix(".") == true)
    }
}
