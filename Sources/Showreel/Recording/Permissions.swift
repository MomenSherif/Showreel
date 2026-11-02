import AppKit
import AVFoundation
import CoreGraphics

/// The access Showreel needs (S-001). Screen Recording is required;
/// Microphone and Camera are optional.
@Observable
final class Permissions {
    static let shared = Permissions()

    enum Kind: String, CaseIterable, Identifiable {
        case screen, microphone, camera
        var id: String { rawValue }

        var title: String {
            switch self {
            case .screen: "Screen Recording"
            case .microphone: "Microphone"
            case .camera: "Camera"
            }
        }

        var reason: String {
            switch self {
            case .screen: "To record your displays and windows."
            case .microphone: "To record your voice (optional)."
            case .camera: "To show you in a Camera Bubble (optional)."
            }
        }

        var symbol: String {
            switch self {
            case .screen: "rectangle.dashed.badge.record"
            case .microphone: "mic"
            case .camera: "video"
            }
        }

        var settingsURL: URL {
            let pane = switch self {
            case .screen: "Privacy_ScreenCapture"
            case .microphone: "Privacy_Microphone"
            case .camera: "Privacy_Camera"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        }
    }

    enum State: Equatable {
        case allowed, notAllowed
        /// Screen Recording was granted, but macOS applies it only after a relaunch.
        case needsRelaunch
    }

    private(set) var screen: State = .notAllowed
    private(set) var microphone: State = .notAllowed
    private(set) var camera: State = .notAllowed
    /// Set when the person asked for Screen Recording in this run.
    @ObservationIgnored private var askedForScreen = false
    @ObservationIgnored private var timer: Timer?

    private init() { refresh() }

    func state(_ kind: Kind) -> State {
        switch kind {
        case .screen: screen
        case .microphone: microphone
        case .camera: camera
        }
    }

    var canRecord: Bool { screen == .allowed }

    func refresh() {
        let screenNow = CGPreflightScreenCaptureAccess()
        let next: State = screenNow ? .allowed : (askedForScreen && Self.grantedInSettings ? .needsRelaunch : .notAllowed)
        if screen != next { screen = next }
        let mic: State = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? .allowed : .notAllowed
        if microphone != mic { microphone = mic }
        let cam: State = AVCaptureDevice.authorizationStatus(for: .video) == .authorized ? .allowed : .notAllowed
        if camera != cam { camera = cam }
    }

    /// CGPreflightScreenCaptureAccess stays false until relaunch. The window
    /// list shows other apps' window names only once access is granted, so
    /// that tells us the person switched it on in System Settings.
    private static var grantedInSettings: Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        return list.contains { ($0[kCGWindowOwnerPID as String] as? Int32) != mine && $0[kCGWindowName as String] != nil }
    }

    /// Microphone and Camera show the system prompt the first time, and
    /// open System Settings after a refusal. Screen Recording always goes
    /// through System Settings.
    func request(_ kind: Kind) {
        switch kind {
        case .screen:
            if !CGPreflightScreenCaptureAccess() { resetOnce(kind) }
            askedForScreen = true
            if !CGRequestScreenCaptureAccess() { NSWorkspace.shared.open(kind.settingsURL) }
        case .microphone, .camera:
            let media: AVMediaType = kind == .camera ? .video : .audio
            if AVCaptureDevice.authorizationStatus(for: media) == .denied { resetOnce(kind) }
            if AVCaptureDevice.authorizationStatus(for: media) == .notDetermined {
                AVCaptureDevice.requestAccess(for: media) { @Sendable _ in
                    Task { @MainActor in Permissions.shared.refresh() }
                }
            } else {
                NSWorkspace.shared.open(kind.settingsURL)
            }
        }
        refresh()
    }

    @ObservationIgnored private var reset: Set<Kind> = []

    /// macOS keeps a permission for the signature that got it. A copy signed
    /// differently (an older release, or a local build) leaves a row in
    /// System Settings that is switched on but does not apply to this copy,
    /// and while that row exists macOS never asks again. Clearing our own
    /// row lets the request below add a fresh one for this copy.
    ///
    /// Once per launch only: a grant made after this launch reads as "not
    /// allowed" until relaunch, and a second reset would throw it away.
    private func resetOnce(_ kind: Kind) {
        guard reset.insert(kind).inserted, let id = Bundle.main.bundleIdentifier else { return }
        let service = switch kind {
        case .screen: "ScreenCapture"
        case .microphone: "Microphone"
        case .camera: "Camera"
        }
        let tccutil = Process()
        tccutil.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tccutil.arguments = ["reset", service, id]
        tccutil.standardOutput = FileHandle.nullDevice
        tccutil.standardError = FileHandle.nullDevice
        do {
            try tccutil.run()
            tccutil.waitUntilExit()
        } catch {}
    }

    /// Checks every second while a view that shows permissions is open.
    func startWatching() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { Permissions.shared.refresh() }
        }
        timer?.tolerance = 0.2
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    /// Quits and opens a fresh copy, so a new Screen Recording grant applies.
    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
