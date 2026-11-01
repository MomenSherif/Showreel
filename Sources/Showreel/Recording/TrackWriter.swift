import AVFoundation
import CoreMedia
import Synchronization
import ShowreelKit

/// The recording clock shared by every track and the event log. Samples
/// carry host-clock times; the timeline turns them into recording time with
/// pauses removed, so all files line up (S-007).
nonisolated final class Timeline: Sendable {
    private let clock = Mutex(RecordingClock())

    static var hostNow: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    func begin(at host: Double = Timeline.hostNow) { clock.withLock { $0.begin(at: host) } }
    func pause(at host: Double = Timeline.hostNow) { clock.withLock { $0.pause(at: host) } }
    func resume(at host: Double = Timeline.hostNow) { clock.withLock { $0.resume(at: host) } }
    func mediaTime(at host: Double) -> Double? { clock.withLock { $0.mediaTime(at: host) } }
    func elapsed(at host: Double = Timeline.hostNow) -> Double { clock.withLock { $0.elapsed(at: host) } }
    var isStarted: Bool { clock.withLock { $0.isStarted } }
    var isPaused: Bool { clock.withLock { $0.isPaused } }
}

/// Writes one track (screen, camera, mic, or system audio) to its own file.
/// Samples arrive on capture queues; everything here runs on `queue`.
nonisolated final class TrackWriter: @unchecked Sendable {
    // @unchecked: every mutable property is touched only on `queue`.
    enum Kind: Sendable {
        case video(width: Int, height: Int, bitrate: Int)
        case audio(channels: Int, bitrate: Int)
    }

    let url: URL
    private let kind: Kind
    private let timeline: Timeline
    private let queue: DispatchQueue
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var lastTime = -1.0
    /// The newest video frame, kept so a still screen still has a first and last frame.
    private var lastFrame: CMSampleBuffer?
    private(set) var appended = 0

    init(url: URL, kind: Kind, timeline: Timeline) throws {
        self.url = url
        self.kind = kind
        self.timeline = timeline
        queue = DispatchQueue(label: "showreel.writer.\(url.lastPathComponent)", qos: .userInitiated)
        try? FileManager.default.removeItem(at: url)
        switch kind {
        case let .video(width, height, bitrate):
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoExpectedSourceFrameRateKey: 60,
                    AVVideoAllowFrameReorderingKey: false,
                ],
            ])
        case let .audio(channels, bitrate):
            writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: bitrate,
            ])
        }
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
    }

    /// Takes a sample stamped `host` seconds (host clock).
    func append(_ buffer: CMSampleBuffer, host: Double) {
        let sample = Sample(buffer: buffer)
        queue.async { [self] in
            if case .video = kind { lastFrame = sample.buffer }
            guard let time = timeline.mediaTime(at: host) else { return }
            write(sample.buffer, at: time)
        }
    }

    /// Carries a sample buffer to the writer queue. @unchecked: a
    /// CMSampleBuffer is immutable once made, and only this queue uses it.
    private struct Sample: @unchecked Sendable { let buffer: CMSampleBuffer }

    /// Called when the clock starts: puts the newest frame at 0, so the
    /// video has a picture from the first instant even if nothing moves.
    func primeFirstFrame() {
        queue.async { [self] in
            if appended == 0, let lastFrame { write(lastFrame, at: 0) }
        }
    }

    /// Repeats the newest frame at `end`, then closes the file.
    func finish(at end: Double) async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            queue.async { [self] in
                if case .video = kind, let lastFrame, end > lastTime + 0.001 { write(lastFrame, at: end) }
                guard writer.status == .writing else { done.resume(returning: false); return }
                input.markAsFinished()
                if appended == 0 {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    done.resume(returning: false)
                    return
                }
                writer.endSession(atSourceTime: CMTime(seconds: max(end, lastTime), preferredTimescale: 600))
                writer.finishWriting { [self] in done.resume(returning: writer.status == .completed) }
            }
        }
    }

    /// Stops without saving (Restart).
    func cancel() {
        queue.async { [self] in
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func write(_ buffer: CMSampleBuffer, at time: Double) {
        guard writer.status == .writing, time > lastTime, input.isReadyForMoreMediaData else { return }
        // One timing entry covers every sample in the buffer, so for audio
        // its duration is one sample, not the whole buffer.
        let duration: CMTime = switch kind {
        case .video: buffer.duration
        case .audio: CMTime(value: 1, timescale: 48_000)
        }
        var timing = CMSampleTimingInfo(duration: duration,
                                        presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 48_000),
                                        decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: buffer,
                                              sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                              sampleBufferOut: &copy)
        guard let copy, input.append(copy) else { return }
        lastTime = time
        appended += 1
    }
}
