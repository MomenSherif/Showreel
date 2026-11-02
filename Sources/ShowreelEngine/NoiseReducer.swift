import AudioToolbox
import AVFoundation

/// Reduce Noise (S-043): runs the mic track through Apple's voice isolation
/// Audio Unit (AUSoundIsolation) on this Mac and writes a clean copy. The
/// original file never changes, so turning it off brings the room back.
public enum NoiseReducer {
    public enum Failure: Error {
        /// This Mac has no voice isolation unit.
        case unavailable
    }

    static let description = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                                       componentSubType: kAudioUnitSubType_AUSoundIsolation,
                                                       componentManufacturer: kAudioUnitManufacturer_Apple,
                                                       componentFlags: 0, componentFlagsMask: 0)

    public static var isAvailable: Bool {
        var description = Self.description
        return AudioComponentFindNext(nil, &description) != nil
    }

    /// Writes `input` with the background noise removed to `output` (AAC).
    /// `progress` gets 0...1. Cancelling stops it and deletes the output.
    public static func clean(_ input: URL, to output: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard isAvailable else { throw Failure.unavailable }
        try? FileManager.default.removeItem(at: output)
        do {
            // The work is synchronous; it runs off the caller's thread.
            try await Task.detached(priority: .userInitiated) {
                try render(input, to: output, progress: progress)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private static func render(_ input: URL, to output: URL, progress: @Sendable (Double) -> Void) throws {
        let file = try AVAudioFile(forReading: input)
        // The voice unit works at 48 kHz; a mixer in front resamples any other rate.
        let source = file.processingFormat
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: source.channelCount) else { return }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let resample = AVAudioMixerNode()
        let isolation = AVAudioUnitEffect(audioComponentDescription: description)
        [player, resample, isolation].forEach(engine.attach)
        engine.connect(player, to: resample, format: source)
        engine.connect(resample, to: isolation, format: format)
        engine.connect(isolation, to: engine.mainMixerNode, format: format)
        let chunk: AVAudioFrameCount = 4_096
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunk)
        try engine.start()
        defer { engine.stop() }
        player.scheduleFile(file, at: nil)
        player.play()

        let out = try AVAudioFile(forWriting: output, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 128_000,
        ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunk) else { return }
        let total = AVAudioFramePosition((Double(file.length) * format.sampleRate / source.sampleRate).rounded())
        var done: AVAudioFramePosition = 0
        while done < total {
            try Task.checkCancellation()
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(chunk), total - done))
            guard try engine.renderOffline(frames, to: buffer) == .success else { break }
            try out.write(from: buffer)
            done += AVAudioFramePosition(buffer.frameLength)
            progress(Double(done) / Double(max(total, 1)))
        }
    }
}
