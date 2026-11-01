import AVFoundation
import CoreMedia

/// One capture session for one device (a mic or a camera). It runs while the
/// Record Panel shows the device, so the level meter and the Camera Bubble
/// are live, and the recorder reads its samples from the same session.
public final class DeviceCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    // @unchecked: `session` is configured once before it starts. `sink` is
    // read and written only on `queue`, the delegate queue.
    public enum Media: Sendable { case audio, video }

    public let media: Media
    public let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "showreel.capture.device", qos: .userInitiated)
    private var sink: (@Sendable (CMSampleBuffer) -> Void)?
    public private(set) var dimensions = CMVideoDimensions(width: 1280, height: 720)

    public init?(media: Media, deviceID: String) {
        self.media = media
        super.init()
        guard let device = AVCaptureDevice(uniqueID: deviceID),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return nil }
        session.beginConfiguration()
        session.addInput(input)
        switch media {
        case .video:
            if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else { return nil }
            session.addOutput(output)
            dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        case .audio:
            let output = AVCaptureAudioDataOutput()
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
            ]
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else { return nil }
            session.addOutput(output)
        }
        session.commitConfiguration()
    }

    public func start() { queue.async { self.session.startRunning() } }
    public func stop() { queue.async { self.session.stopRunning() } }

    /// Samples go to `sink` (the recorder) until it is set to nil.
    public func setSink(_ sink: (@Sendable (CMSampleBuffer) -> Void)?) {
        queue.async { self.sink = sink }
    }

    /// The input level in dBFS, about -60 (silent) to 0, read by the level meter.
    public var level: Float {
        session.outputs.first?.connections.first?.audioChannels.first?.averagePowerLevel ?? -160
    }

    /// Sample times from this session, in host-clock seconds.
    public func hostSeconds(_ buffer: CMSampleBuffer) -> Double {
        let pts = buffer.presentationTimeStamp
        guard let clock = session.synchronizationClock else { return pts.seconds }
        return CMSyncConvertTime(pts, from: clock, to: CMClockGetHostTimeClock()).seconds
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        sink?(sampleBuffer)
    }
}
