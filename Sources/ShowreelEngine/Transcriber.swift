import AVFoundation
import Foundation
import Speech
import ShowreelKit

/// Turns a voice recording into timed words with SpeechAnalyzer, on this
/// Mac (S-039). Nothing leaves the Mac; the speech model is downloaded once
/// by the system when it is missing.
public enum Transcriber {
    /// What it is doing, for the progress bar.
    public enum Phase: Equatable, Sendable {
        /// Downloading the speech model, 0...1.
        case downloading(Double)
        /// Listening to the recording, 0...1.
        case listening(Double)
    }

    public enum Failure: Error, Equatable {
        /// No speech model for this language.
        case unsupportedLanguage(Locale)
        /// The file has no audio track.
        case unreadable
    }

    /// The words in the audio file at `url`, in the language closest to
    /// `locale`, and the language used. Cancelling the task stops it.
    public static func words(in url: URL, locale: Locale = .current,
                             progress: @escaping @Sendable (Phase) -> Void) async throws -> (words: [CaptionWord], locale: Locale) {
        guard let language = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw Failure.unsupportedLanguage(locale)
        }
        let transcriber = SpeechTranscriber(locale: language, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let watch = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in
                progress(.downloading(p.fractionCompleted))
            }
            defer { watch.invalidate() }
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()

        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw Failure.unreadable }
        let seconds = Double(file.length) / max(file.processingFormat.sampleRate, 1)
        progress(.listening(0))

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collect = Task {
            var words: [CaptionWord] = []
            for try await result in transcriber.results {
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    words.append(CaptionWord(text: String(result.text[run.range].characters),
                                             start: range.start.seconds, end: range.end.seconds))
                }
                if seconds > 0 { progress(.listening(min(1, result.range.end.seconds / seconds))) }
            }
            return words
        }
        try await withTaskCancellationHandler {
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } onCancel: {
            collect.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
        try Task.checkCancellation()
        let words = try await collect.value
        progress(.listening(1))
        return (words.sorted { $0.start < $1.start }, language)
    }
}
