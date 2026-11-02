import AVFoundation
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

    /// S-042: the waveform is loud where the voice is, and spans the whole file.
    @Test func waveformFollowsTheVoice() async throws {
        let url = try speech("Hello there, this is a test of the waveform.")
        defer { try? FileManager.default.removeItem(at: url) }
        let wave = try #require(await WaveformReader.read(url))
        #expect(wave.peaksPerSecond == 50)
        #expect(wave.peak(from: 0.3, to: 1.5) > 0.1)
        #expect(wave.peaks.allSatisfy { $0 >= 0 && $0 <= 1 })
        let seconds = Double(wave.peaks.count) / wave.peaksPerSecond
        #expect(seconds > 1.5 && seconds < 8, "\(seconds) s")
    }

    /// S-043: Reduce Noise removes a steady hum and hiss, and the voice in
    /// the cleaned file is still understood word for word.
    @Test(.enabled(if: NoiseReducer.isAvailable && SpeechTranscriber.isAvailable), .timeLimit(.minutes(5)))
    func reduceNoiseRemovesHumAndKeepsTheVoice() async throws {
        let voice = try speech("This is a test of noise reduction. The fan in the room is humming while I talk.")
        let noisy = FileManager.default.temporaryDirectory.appendingPathComponent("noisy-\(UUID().uuidString).caf")
        let clean = FileManager.default.temporaryDirectory.appendingPathComponent("clean-\(UUID().uuidString).m4a")
        defer { [voice, noisy, clean].forEach { try? FileManager.default.removeItem(at: $0) } }
        try addFanNoise(to: voice, writing: noisy)
        try await NoiseReducer.clean(noisy, to: clean) { _ in }

        let before = try #require(await WaveformReader.read(noisy)), after = try #require(await WaveformReader.read(clean))
        // The first second is noise only.
        #expect(before.peak(from: 0.2, to: 0.9) > 0.1)
        #expect(after.peak(from: 0.2, to: 0.9) < before.peak(from: 0.2, to: 0.9) / 10,
                "noise peaks at \(after.peak(from: 0.2, to: 0.9)) after, \(before.peak(from: 0.2, to: 0.9)) before")
        #expect(after.peak(from: 1.5, to: 3) > 0.05, "the voice is still there")
        let (words, _) = try await Transcriber.words(in: clean, locale: Locale(identifier: "en_US")) { _ in }
        let text = words.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ").lowercased()
        #expect(text.contains("noise reduction"), "heard: \(text)")
    }

    /// The voice 1 second in, over a 120 Hz hum with its harmonic and hiss, at 48 kHz.
    private func addFanNoise(to url: URL, writing out: URL) throws {
        let input = try AVAudioFile(forReading: url)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let converter = try #require(AVAudioConverter(from: input.processingFormat, to: format))
        nonisolated(unsafe) let source = try #require(AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)))
        try input.read(into: source)
        let lead = 48_000
        let capacity = AVAudioFrameCount(Double(input.length) * 48_000 / input.processingFormat.sampleRate) + 4_096
        let voice = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity))
        nonisolated(unsafe) var given = false
        _ = converter.convert(to: voice, error: nil) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return source
        }
        let total = Int(voice.frameLength) + lead
        let mixed = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)))
        mixed.frameLength = AVAudioFrameCount(total)
        let v = try #require(voice.floatChannelData?[0]), m = try #require(mixed.floatChannelData?[0])
        var seed: UInt64 = 7
        for i in 0..<total {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let hiss = Float(Int64(bitPattern: seed >> 11) % 1000) / 1000 * 0.04
            let t = Double(i) / 48_000
            let hum = Float(0.08 * sin(2 * .pi * 120 * t) + 0.05 * sin(2 * .pi * 240 * t))
            m[i] = hum + hiss + (i >= lead ? v[i - lead] : 0)
        }
        let file = try AVAudioFile(forWriting: out, settings: format.settings)
        try file.write(from: mixed)
    }
}
