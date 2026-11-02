import AVFoundation
import CoreImage
import ImageIO
import ShowreelKit
import Synchronization
import UniformTypeIdentifiers

/// Why an export stopped.
public enum ExportError: LocalizedError, Equatable {
    case cannotRead(String)
    case cannotWrite(String)

    public var errorDescription: String? {
        switch self {
        case .cannotRead(let why): "The recording could not be read. \(why)"
        case .cannotWrite(let why): "The file could not be written. \(why)"
        }
    }
}

/// Renders a project to a file (S-036). The frames come from the same
/// video composition the preview plays, so `Renderer` draws both and they
/// cannot drift apart; only the render size and frame rate differ.
public enum Exporter {
    /// Writes `asset`, drawn by `videoComposition`, to `url` as
    /// `settings.format`. The composition's render size is the output size
    /// and its frame duration the frame rate. `progress` gets 0...1 from any
    /// thread. Cancelling the task stops the export and deletes the file.
    /// `audioLevels` sets the tracks' volumes and muted parts, as the preview plays them (S-042).
    public static func export(asset: AVAsset, videoComposition: AVVideoComposition, audioLevels: AudioLevels? = nil,
                              settings: ExportSettings,
                              to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        do {
            if settings.format == .gif {
                try await gif(asset: asset, videoComposition: videoComposition, settings: settings, to: url, progress: progress)
            } else {
                try await movie(asset: asset, videoComposition: videoComposition, audioLevels: audioLevels, settings: settings,
                                to: url, progress: progress)
            }
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    // MARK: MP4 and MOV

    private static func movie(asset: AVAsset, videoComposition: AVVideoComposition, audioLevels: AudioLevels?, settings: ExportSettings,
                              to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let duration = try await asset.load(.duration)
        let size = videoComposition.renderSize
        let reader = try AVAssetReader(asset: asset)
        let video = try await videoOutput(asset: asset, videoComposition: videoComposition)
        reader.add(video)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audio: AVAssetReaderAudioMixOutput?
        if settings.format.hasAudio, !audioTracks.isEmpty {
            // The mic and system audio mixed into one stereo track, as the preview plays them.
            let mix = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            mix.audioMix = audioLevels?.audioMix()
            if reader.canAdd(mix) { reader.add(mix); audio = mix }
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: settings.format == .mov ? .mov : .mp4)
        writer.shouldOptimizeForNetworkUse = true
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.videoBitrate(size: size),
            AVVideoExpectedSourceFrameRateKey: settings.fps,
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
        ]
        if settings.format == .mp4 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: settings.format == .mov ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compression,
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw ExportError.cannotWrite("The video settings are not supported.") }
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if audio != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: ExportSettings.audioBitrate,
            ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) { writer.add(input); audioInput = input }
        }

        guard writer.startWriting() else { throw ExportError.cannotWrite(writer.error?.localizedDescription ?? "") }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else { throw ExportError.cannotRead(reader.error?.localizedDescription ?? "") }

        // Cancel only raises this flag. The pumps see it between samples and
        // stop; the reader is cancelled after both have stopped. Cancelling it
        // while a pump is inside copyNextSampleBuffer() crashed (FIXLOG).
        let stop = StopFlag()
        let total = max(duration.seconds, 0.001)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                // Both tracks move at once: the writer interleaves them and
                // waits for the one that falls behind.
                let group = DispatchGroup()
                pump(video, into: videoInput, label: "video", group: group, stop: stop) { time in
                    progress(min(max(time.seconds / total, 0), 1))
                }
                if let audio, let audioInput { pump(audio, into: audioInput, label: "audio", group: group, stop: stop) { _ in } }
                group.notify(queue: .global()) { done.resume() }
            }
        } onCancel: {
            stop.raise()
        }

        if Task.isCancelled || stop.isRaised {
            reader.cancelReading()
            writer.cancelWriting()
            throw CancellationError()
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw ExportError.cannotRead(reader.error?.localizedDescription ?? "")
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw ExportError.cannotWrite(writer.error?.localizedDescription ?? "") }
        progress(1)
    }

    /// Moves samples from `output` to `input` on their own queue until the
    /// output runs dry, inside `group`.
    private static func pump(_ output: AVAssetReaderOutput, into input: AVAssetWriterInput, label: String,
                             group: DispatchGroup, stop: StopFlag,
                             appended: @escaping @Sendable (CMTime) -> Void) {
        let queue = DispatchQueue(label: "com.momensherif.showreel.export.\(label)")
        let pair = Unchecked((output: output, input: input, once: Once()))
        group.enter()
        input.requestMediaDataWhenReady(on: queue) {
            let (output, input, once) = pair.value
            while input.isReadyForMoreMediaData {
                // Nil when the output is done or the reader failed; a failed
                // append means the writer failed; `stop` means Cancel. The
                // caller reads which.
                guard !stop.isRaised, let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                    input.markAsFinished()
                    if once.claim() { group.leave() }
                    return
                }
                appended(CMSampleBufferGetPresentationTimeStamp(sample))
            }
        }
    }

    private static func videoOutput(asset: AVAsset, videoComposition: AVVideoComposition) async throws -> AVAssetReaderVideoCompositionOutput {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { throw ExportError.cannotRead("It has no video.") }
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.videoComposition = videoComposition
        output.alwaysCopiesSampleData = false
        return output
    }

    // MARK: GIF

    private static func gif(asset: AVAsset, videoComposition: AVVideoComposition, settings: ExportSettings,
                            to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let duration = try await asset.load(.duration).seconds
        let reader = try AVAssetReader(asset: asset)
        let video = try await videoOutput(asset: asset, videoComposition: videoComposition)
        reader.add(video)
        let count = max(1, Int((duration * Double(settings.fps)).rounded()))
        let delays = ExportSettings.gifDelays(frames: count, fps: settings.fps)
        guard let file = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw ExportError.cannotWrite("")
        }
        CGImageDestinationSetProperties(file, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        guard reader.startReading() else { throw ExportError.cannotRead(reader.error?.localizedDescription ?? "") }

        let context = CIContext(options: [.cacheIntermediates: false])
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        var written = 0
        var last: CGImage?
        func add(_ image: CGImage) {
            CGImageDestinationAddImage(file, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(delays[written]) / 100],
            ] as CFDictionary)
            written += 1
            progress(Double(written) / Double(count))
        }
        while written < count, let sample = video.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let picture = CIImage(cvPixelBuffer: pixels)
            guard let image = context.createCGImage(picture, from: picture.extent, format: .RGBA8, colorSpace: sRGB) else { continue }
            add(image)
            last = image
        }
        if reader.status == .failed { throw ExportError.cannotRead(reader.error?.localizedDescription ?? "") }
        // The reader can end a frame early: hold the last picture.
        while written < count, let last { add(last) }
        guard written > 0, CGImageDestinationFinalize(file) else { throw ExportError.cannotWrite("") }
        reader.cancelReading()
    }
}

/// Carries AVFoundation objects into the callbacks they hand out, which run
/// on one serial queue each.
private final class Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// True the first time only, so a continuation resumes once.
/// Raised once by Cancel, read by the pumps on their queues.
private final class StopFlag: Sendable {
    private let raised = Mutex(false)
    func raise() { raised.withLock { $0 = true } }
    var isRaised: Bool { raised.withLock { $0 } }
}

private final class Once {
    private var used = false
    func claim() -> Bool {
        if used { return false }
        used = true
        return true
    }
}
