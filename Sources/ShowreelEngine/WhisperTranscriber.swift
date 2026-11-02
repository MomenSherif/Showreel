import AVFoundation
import Foundation
import Synchronization
import ShowreelKit
import whisper

/// Turns a voice recording into timed words with a Whisper model through
/// whisper.cpp on the GPU (S-052), on this Mac. It takes the same path as
/// Apple's `Transcriber`: words with times, grouped into lines by
/// `CaptionTrack.lines`. Arabic speech gets a mixed prompt so English words
/// stay in Latin letters (S-053).
public enum WhisperTranscriber {
    public enum Failure: Error, Equatable {
        /// The model file would not load.
        case modelUnreadable
        /// The file has no audio track.
        case unreadable
        case failed
    }

    /// Whisper wants 16 kHz mono samples.
    static let sampleRate = 16_000.0

    /// The words in the audio at `url`, and the language code used ("ar",
    /// "en"). `language` is a Whisper code or "auto". Cancelling the task
    /// stops it within one decoding step and frees the model.
    public static func words(in url: URL, model: URL, language: String = CaptionLanguage.automatic,
                             progress: @escaping @Sendable (Transcriber.Phase) -> Void) async throws -> (words: [CaptionWord], language: String) {
        let samples = try await Task.detached(priority: .userInitiated) { try loadSamples(url) }.value
        try Task.checkCancellation()
        let run = Run(progress: progress)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try transcribe(samples, model: model, language: language, run: run)
            }.value
        } onCancel: {
            run.cancelled.store(true, ordering: .relaxed)
        }
    }

    /// What the C callbacks reach through their user data.
    final class Run: Sendable {
        let cancelled = Atomic<Bool>(false)
        let progress: @Sendable (Transcriber.Phase) -> Void
        init(progress: @escaping @Sendable (Transcriber.Phase) -> Void) { self.progress = progress }
    }

    static func transcribe(_ samples: [Float], model: URL, language: String, run: Run) throws -> (words: [CaptionWord], language: String) {
        quiet()
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(model.path, cparams) else { throw Failure.modelUnreadable }
        defer { whisper_free(ctx) }
        if run.cancelled.load(ordering: .relaxed) { throw CancellationError() }
        run.progress(.listening(0))

        let threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        // Automatic: find the language first, so Arabic gets its prompt.
        var code = language
        if code == CaptionLanguage.automatic {
            code = detectLanguage(ctx, samples, threads: threads) ?? CaptionLanguage.automatic
        }
        if run.cancelled.load(ordering: .relaxed) { throw CancellationError() }

        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        params.beam_search.beam_size = 5
        params.n_threads = threads
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = false
        params.suppress_nst = true
        // One word per segment, with its own start and end.
        params.token_timestamps = true
        params.max_len = 1
        params.split_on_word = true

        let box = Unmanaged.passRetained(run)
        defer { box.release() }
        params.progress_callback = { _, _, percent, user in
            guard let user else { return }
            Unmanaged<Run>.fromOpaque(user).takeUnretainedValue().progress(.listening(Double(percent) / 100))
        }
        params.progress_callback_user_data = box.toOpaque()
        params.abort_callback = { user in
            guard let user else { return false }
            return Unmanaged<Run>.fromOpaque(user).takeUnretainedValue().cancelled.load(ordering: .relaxed)
        }
        params.abort_callback_user_data = box.toOpaque()

        let prompt = CaptionLanguage.prompt(for: code)
        let status: Int32 = code.withCString { lang in
            withOptionalCString(prompt) { promptPointer in
                params.language = lang
                params.initial_prompt = promptPointer
                return samples.withUnsafeBufferPointer { whisper_full(ctx, params, $0.baseAddress, Int32($0.count)) }
            }
        }
        if run.cancelled.load(ordering: .relaxed) { throw CancellationError() }
        guard status == 0 else { throw Failure.failed }

        var words: [CaptionWord] = []
        for i in 0..<whisper_full_n_segments(ctx) {
            guard let raw = whisper_full_get_segment_text(ctx, i) else { continue }
            let text = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isNoise(text) else { continue }
            // Times are in hundredths of a second.
            let start = Double(whisper_full_get_segment_t0(ctx, i)) / 100
            let end = max(Double(whisper_full_get_segment_t1(ctx, i)) / 100, start + 0.05)
            words.append(CaptionWord(text: text, start: start, end: end))
        }
        let detected = String(cString: whisper_lang_str(whisper_full_lang_id(ctx)))
        run.progress(.listening(1))
        return (words, code == CaptionLanguage.automatic ? detected : code)
    }

    /// The language spoken in the first 30 seconds, or nil.
    static func detectLanguage(_ ctx: OpaquePointer, _ samples: [Float], threads: Int32) -> String? {
        let head = Array(samples.prefix(Int(sampleRate * 30)))
        let ok = head.withUnsafeBufferPointer { whisper_pcm_to_mel(ctx, $0.baseAddress, Int32($0.count), threads) }
        guard ok == 0 else { return nil }
        let id = whisper_lang_auto_detect(ctx, 0, threads, nil)
        guard id >= 0, let name = whisper_lang_str(id) else { return nil }
        return String(cString: name)
    }

    /// "[Music]", "(applause)", "♪": sounds, not words.
    static func isNoise(_ text: String) -> Bool {
        (text.hasPrefix("[") && text.hasSuffix("]")) || (text.hasPrefix("(") && text.hasSuffix(")")) || text.allSatisfy { "♪♫ ".contains($0) }
    }

    /// The recording as 16 kHz mono floats.
    static func loadSamples(_ url: URL) throws -> [Float] {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw Failure.unreadable }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target) else { throw Failure.unreadable }
        let chunk: AVAudioFrameCount = 1 << 16
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { throw Failure.unreadable }
        // The converter calls back on this thread, synchronously.
        nonisolated(unsafe) let input = buffer
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * sampleRate / max(file.processingFormat.sampleRate, 1)) + 1024)
        var done = false
        while !done {
            let outCapacity = AVAudioFrameCount(Double(chunk) * sampleRate / max(file.processingFormat.sampleRate, 1)) + 1024
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity) else { throw Failure.unreadable }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                do {
                    try file.read(into: input, frameCount: chunk)
                } catch {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if input.frameLength == 0 {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return input
            }
            if let channel = output.floatChannelData?[0], output.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
            switch status {
            case .endOfStream, .error: done = true
            default: break
            }
            if error != nil { throw Failure.unreadable }
        }
        return samples
    }

    /// whisper.cpp logs every layer to stderr; captions need none of it.
    static func quiet() {
        whisper_log_set({ _, _, _ in }, nil)
    }

    static func withOptionalCString<R>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
        guard let string else { return body(nil) }
        return string.withCString { body($0) }
    }
}
