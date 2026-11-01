import CoreMedia
import ScreenCaptureKit

/// The ScreenCaptureKit stream: screen frames (cursor hidden) and,
/// optionally, system audio, each sent to its writer.
public final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    // @unchecked: the writers are set before `start` and only read on the
    // stream's queues afterwards; `stream` is touched only from the main actor.
    private let queue = DispatchQueue(label: "showreel.capture.screen", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "showreel.capture.system-audio", qos: .userInitiated)
    private var stream: SCStream?
    private let screenWriter: TrackWriter
    private let audioWriter: TrackWriter?
    private let onError: @Sendable (Error) -> Void

    public init(screenWriter: TrackWriter, audioWriter: TrackWriter?, onError: @escaping @Sendable (Error) -> Void) {
        self.screenWriter = screenWriter
        self.audioWriter = audioWriter
        self.onError = onError
    }

    /// Starts the stream. `width` and `height` are the pixel size of
    /// screen.mov; `sourceRect` is an area inside the display, in points.
    @MainActor
    public func start(filter: SCContentFilter, width: Int, height: Int, sourceRect: CGRect?) async throws {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        if let sourceRect { config.sourceRect = sourceRect }
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        config.queueDepth = 6
        config.capturesAudio = audioWriter != nil
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if audioWriter != nil { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue) }
        try await stream.startCapture()
        self.stream = stream
    }

    @MainActor
    public func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard buffer.isValid else { return }
        let host = buffer.presentationTimeStamp.seconds
        switch type {
        case .screen:
            // Only frames with new content: idle and blank frames carry no picture.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: raw) == .complete else { return }
            screenWriter.append(buffer, host: host)
        case .audio:
            audioWriter?.append(buffer, host: host)
        default:
            break
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(error)
    }
}
