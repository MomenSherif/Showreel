import AVFoundation
import Foundation
import Speech
import Testing
import ShowreelEngine
import ShowreelKit

/// Whisper through whisper.cpp (S-052, S-053). These run when a Whisper
/// model is on this Mac (downloaded, or Handy's); without one they are skipped.
@Suite("Whisper", .serialized)
struct WhisperTests {
    /// The best Whisper model here: Turbo, then Small.
    static let model: (SpeechModel, URL)? = [SpeechModel.whisperTurbo, .whisperSmall].lazy
        .compactMap { m in ModelLocator.standard.availability(of: m).url.map { (m, $0) } }.first
    static var hasModel: Bool { model != nil }

    /// Speech made with `say`. Parts in different voices are joined, so a
    /// clip can mix Arabic and English like a person does.
    static func speech(_ parts: [(voice: String, text: String)]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "showreel-whisper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1))
        let out = dir.appending(path: "speech.caf")
        let file = try AVAudioFile(forWriting: out, settings: format.settings)
        for (i, part) in parts.enumerated() {
            let piece = dir.appending(path: "\(i).caf")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", part.voice, "-o", piece.path, "--data-format=LEF32@22050", part.text]
            try say.run()
            say.waitUntilExit()
            let input = try AVAudioFile(forReading: piece)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)))
            try input.read(into: buffer)
            try file.write(from: buffer)
        }
        return out
    }

    /// Lowercased, without punctuation, for comparing words.
    static func plain(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" }
    }

    /// S-052: the same words as Apple's model, at about the same times, and
    /// the same 42-character lines.
    @Test(.enabled(if: hasModel && SpeechTranscriber.isAvailable), .timeLimit(.minutes(5)))
    func englishWordsMatchApplesTiming() async throws {
        let (_, model) = try #require(Self.model)
        let url = try Self.speech([("Samantha", "Welcome to the demo. Click the record button to start a new recording, then open it in the editor to add zooms.")])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (whisper, language) = try await WhisperTranscriber.words(in: url, model: model, language: "en") { _ in }
        let (apple, _) = try await Transcriber.words(in: url, locale: Locale(identifier: "en_US")) { _ in }
        #expect(language == "en")
        let text = whisper.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("record button"), "heard: \(text)")
        #expect(zip(whisper, whisper.dropFirst()).allSatisfy { $0.start <= $1.start })
        // Each Whisper word against the same word from Apple's model.
        var used = Set<Int>(), close = 0, matched = 0
        for word in whisper {
            guard let i = apple.indices.first(where: { !used.contains($0) && Self.plain(apple[$0].text) == Self.plain(word.text) })
            else { continue }
            used.insert(i)
            matched += 1
            if abs(apple[i].start - word.start) <= 0.2 { close += 1 }
        }
        #expect(matched >= whisper.count * 3 / 4, "\(matched) of \(whisper.count) words match Apple's")
        #expect(close >= matched * 4 / 5, "\(close) of \(matched) start within 0.2 s of Apple's")
        let lines = CaptionTrack.lines(from: whisper), appleLines = CaptionTrack.lines(from: apple)
        #expect(lines.allSatisfy { $0.text.count <= CaptionTrack.maxCharacters })
        #expect(abs(lines.count - appleLines.count) <= 1, "\(lines.map(\.text)) vs \(appleLines.map(\.text))")
    }

    /// S-053: Arabic with English product words in it (not the prompt's own). Arabic comes out in
    /// Arabic letters, the English words in Latin letters.
    @Test(.enabled(if: hasModel), .timeLimit(.minutes(5)), arguments: ["ar", CaptionLanguage.automatic])
    func mixedArabicKeepsEnglishWords(language: String) async throws {
        let (_, model) = try #require(Self.model)
        let url = try Self.speech([
            ("Majed", "أهلاً بيكم. النهارده هنفتح الـ"), ("Samantha", "invoice"),
            ("Majed", "وبعدين نروح على الإعدادات وناخد الـ"), ("Samantha", "webhook"),
            ("Majed", "ونحطه في المشروع."),
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (words, detected) = try await WhisperTranscriber.words(in: url, model: model, language: language) { _ in }
        let text = words.map(\.text).joined(separator: " ")
        #expect(detected == "ar", "detected \(detected): \(text)")
        let arabic = words.filter { $0.text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) } }
        #expect(arabic.count >= 6, "Arabic words: \(text)")
        let lower = text.lowercased()
        #expect(lower.contains("invoice"), "English kept in Latin letters: \(text)")
        #expect(lower.contains("webhook"), "English kept in Latin letters: \(text)")
        // Lines break between words, never inside one.
        for line in CaptionTrack.lines(from: words) {
            #expect(line.text.count <= CaptionTrack.maxCharacters)
            #expect(Set(line.text.split(separator: " ").map(String.init)).isSubset(of: Set(words.map(\.text))))
        }
    }

    /// Cancelling stops it soon, with a CancellationError.
    @Test(.enabled(if: hasModel), .timeLimit(.minutes(2)))
    func cancelStopsIt() async throws {
        let (_, model) = try #require(Self.model)
        let url = try Self.speech([("Samantha", String(repeating: "This is a long recording that we will stop early. ", count: 60))])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let task = Task { try await WhisperTranscriber.words(in: url, model: model, language: "en") { _ in } }
        try await Task.sleep(for: .seconds(0.8))
        let started = Date.now
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(Date.now.timeIntervalSince(started) < 5)
    }
}
