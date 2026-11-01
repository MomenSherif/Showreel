import AVFoundation
import CoreMedia
import ShowreelKit

/// Microphones and cameras, the saved choice for each, and the fallback
/// when a saved device is gone (S-004, S-005).
@Observable
final class Devices {
    static let shared = Devices()

    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
    }

    private(set) var microphones: [Device] = []
    private(set) var cameras: [Device] = []
    /// The name of a saved device that went away, shown as a warning.
    private(set) var lostMicrophone: String?
    private(set) var lostCamera: String?

    var microphoneID: String? {
        didSet { UserDefaults.standard.set(microphoneID, forKey: "record.microphone"); lostMicrophone = nil }
    }
    var cameraID: String? {
        didSet { UserDefaults.standard.set(cameraID, forKey: "record.camera"); lostCamera = nil }
    }

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        microphoneID = UserDefaults.standard.string(forKey: "record.microphone")
        cameraID = UserDefaults.standard.string(forKey: "record.camera")
        refresh()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Devices.shared.refresh() }
            })
        }
    }

    func refresh() {
        // Remember names before the lists change, to name a device that went away.
        for d in microphones + cameras { knownNames[d.id] = d.name }
        let mics = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
        let cams = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                    mediaType: .video, position: .unspecified).devices
        microphones = mics.map { Device(id: $0.uniqueID, name: $0.localizedName) }
        cameras = cams.map { Device(id: $0.uniqueID, name: $0.localizedName) }

        let mic = DeviceChoice.pick(saved: microphoneID, available: microphones.map(\.id),
                                    systemDefault: AVCaptureDevice.default(for: .audio)?.uniqueID)
        let lostMic = mic.fellBack ? name(of: microphoneID) : nil
        if mic.id != microphoneID { microphoneID = mic.id }
        lostMicrophone = lostMic ?? lostMicrophone

        let cam = DeviceChoice.pick(saved: cameraID, available: cameras.map(\.id),
                                    systemDefault: AVCaptureDevice.default(for: .video)?.uniqueID)
        let lostCam = cam.fellBack ? name(of: cameraID) : nil
        if cam.id != cameraID { cameraID = cam.id }
        lostCamera = lostCam ?? lostCamera
    }

    @ObservationIgnored private var knownNames: [String: String] = [:]

    private func name(of id: String?) -> String? {
        guard let id else { return nil }
        return knownNames[id] ?? "The saved device"
    }

    var microphoneName: String { microphones.first { $0.id == microphoneID }?.name ?? "No Microphone" }
    var cameraName: String { cameras.first { $0.id == cameraID }?.name ?? "No Camera" }
}

/// One capture session for one device (a mic or a camera). It runs while the
/// Record Panel shows the device, so the level meter and the Camera Bubble
/// are live, and the recorder reads its samples from the same session.
nonisolated final class DeviceCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    // @unchecked: `session` is configured once before it starts. `sink` is
    // read and written only on `queue`, the delegate queue.
    enum Media { case audio, video }

    let media: Media
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "showreel.capture.device", qos: .userInitiated)
    private var sink: (@Sendable (CMSampleBuffer) -> Void)?
    private(set) var dimensions = CMVideoDimensions(width: 1280, height: 720)

    init?(media: Media, deviceID: String) {
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

    func start() { queue.async { self.session.startRunning() } }
    func stop() { queue.async { self.session.stopRunning() } }

    /// Samples go to `sink` (the recorder) until it is set to nil.
    func setSink(_ sink: (@Sendable (CMSampleBuffer) -> Void)?) {
        queue.async { self.sink = sink }
    }

    /// The input level in dBFS, about -60 (silent) to 0, read by the level meter.
    var level: Float {
        session.outputs.first?.connections.first?.audioChannels.first?.averagePowerLevel ?? -160
    }

    /// Sample times from this session, in host-clock seconds.
    func hostSeconds(_ buffer: CMSampleBuffer) -> Double {
        let pts = buffer.presentationTimeStamp
        guard let clock = session.synchronizationClock else { return pts.seconds }
        return CMSyncConvertTime(pts, from: clock, to: CMClockGetHostTimeClock()).seconds
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        sink?(sampleBuffer)
    }
}
