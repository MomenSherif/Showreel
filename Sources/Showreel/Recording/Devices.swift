import AVFoundation
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
