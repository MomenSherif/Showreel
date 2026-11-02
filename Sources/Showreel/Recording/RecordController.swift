import AppKit
import AVFoundation
import ScreenCaptureKit
import ShowreelEngine
import ShowreelKit

/// Runs a recording from the Record Panel to the finished project (S-002 to S-007).
///   idle -> panel -> countdown -> recording <-> paused -> saving -> idle
@Observable
final class RecordController {
    static let shared = RecordController()

    enum State: Equatable { case idle, panel, countdown, recording, paused, saving }

    private(set) var state: State = .idle
    var isCapturing: Bool { state == .recording || state == .paused }
    /// Seconds recorded so far, refreshed while recording.
    private(set) var elapsed: Double = 0
    /// The number on the Countdown (3, 2, 1).
    private(set) var countdown = 3
    /// A problem to show inline in the panel or the controls.
    private(set) var problem: String?
    /// Less than 2 GB free on the disk that holds the projects.
    private(set) var lowDisk = false

    // MARK: Choices in the Record Panel (remembered)

    var sourceKind: SourceKind = SourceKind(rawValue: Store.defaults.string(forKey: "record.source") ?? "") ?? .display {
        didSet {
            Store.defaults.set(sourceKind.rawValue, forKey: "record.source")
            if sourceKind == .area, oldValue != .area { AreaSelector.shared.begin() }
        }
    }
    var micOn = Store.defaults.object(forKey: "record.mic") as? Bool ?? true {
        didSet { Store.defaults.set(micOn, forKey: "record.mic"); updateDevices() }
    }
    var cameraOn = Store.defaults.bool(forKey: "record.camera.on") {
        didSet { Store.defaults.set(cameraOn, forKey: "record.camera.on"); updateDevices() }
    }
    var systemAudioOn = Store.defaults.bool(forKey: "record.system") {
        didSet { Store.defaults.set(systemAudioOn, forKey: "record.system") }
    }

    /// Displays and windows that can be recorded, loaded when the panel opens.
    private(set) var displays: [SCDisplay] = []
    private(set) var windows: [SCWindow] = []
    var displayID: CGDirectDisplayID? = (Store.defaults.object(forKey: "record.display") as? UInt32) {
        didSet { Store.defaults.set(displayID, forKey: "record.display") }
    }
    var windowID: CGWindowID? {
        didSet { if windowID != nil { windowGone = false } }
    }
    /// The chosen window was closed.
    private(set) var windowGone = false
    /// The dragged-out area, in global top-left points.
    var area: CGRect?
    @ObservationIgnored private var app: SCRunningApplication?

    // MARK: Live devices

    @ObservationIgnored private(set) var mic: DeviceCapture?
    @ObservationIgnored private(set) var camera: DeviceCapture?
    /// The mic level, observed only by the meter (15 Hz).
    @ObservationIgnored let meter = MicMeter()

    // MARK: The recording in progress

    @ObservationIgnored private var timeline: Timeline?
    @ObservationIgnored private var writers: [TrackWriter] = []
    @ObservationIgnored private var screen: ScreenCapture?
    @ObservationIgnored private var events: EventRecorder?
    @ObservationIgnored private var projectID: UUID?
    @ObservationIgnored private var source: CaptureSource?
    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    private(set) var cameraHidden = false

    private init() {}

    // MARK: Entry points

    /// File > New Recording, the menu bar, the Dock menu, ⌘N.
    func newRecording(fromShortcut: Bool = false) {
        guard state == .idle || state == .panel else { return }
        if !Permissions.shared.canRecord && !Store.defaults.bool(forKey: "welcome.done") {
            AppServices.shared.openWelcome()
            return
        }
        state = .panel
        problem = nil
        RecordPanel.shared.show(activate: fromShortcut)
        updateDevices()
        Task { await loadContent() }
        StatusItem.shared.update()
    }

    /// ⌃⌥⌘R: opens the panel, starts from the open panel, or stops.
    func toggleFromShortcut() {
        switch state {
        case .idle: newRecording(fromShortcut: true)
        case .panel: start()
        case .countdown: cancelCountdown(reason: "shortcut")
        case .recording, .paused: stop()
        case .saving: break
        }
    }

    func closePanel() {
        guard state == .panel else { return }
        RecordPanel.shared.hide()
        AreaSelector.shared.cancel()
        state = .idle
        updateDevices()
        StatusItem.shared.update()
    }

    // MARK: Content

    func loadContent() async {
        guard Permissions.shared.canRecord else { problem = nil; return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let me = Bundle.main.bundleIdentifier
            app = content.applications.first { $0.bundleIdentifier == me }
            displays = content.displays
            windows = content.windows
                .filter { $0.isOnScreen && $0.windowLayer == 0 && $0.frame.width >= 120 && $0.frame.height >= 80 }
                .filter { $0.owningApplication?.bundleIdentifier != me && !($0.title ?? "").isEmpty }
            if let id = windowID, !windows.contains(where: { $0.windowID == id }) {
                windowID = nil
                windowGone = true
            }
            if displayID == nil || !displays.contains(where: { $0.displayID == displayID }) {
                displayID = displays.first { $0.displayID == CGMainDisplayID() }?.displayID ?? displays.first?.displayID
            }
        } catch {
            problem = "Unable to list displays and windows. Check Screen Recording access."
        }
    }

    var chosenDisplay: SCDisplay? { displays.first { $0.displayID == displayID } }
    var chosenWindow: SCWindow? { windows.first { $0.windowID == windowID } }

    /// Why Start Recording is disabled, or nil when it can start.
    var startBlocker: String? {
        if !Permissions.shared.canRecord { return "Screen Recording is required to record." }
        switch sourceKind {
        case .display: return chosenDisplay == nil ? "Choose a display." : nil
        case .window: return chosenWindow == nil ? (windowGone ? "That window was closed. Choose a window." : "Choose a window.") : nil
        case .area:
            guard let area else { return "Drag to select an area." }
            return AreaRules.isLargeEnough(area) ? nil : "Area is too small."
        }
    }

    private func resolveSource() -> CaptureSource? {
        switch sourceKind {
        case .display:
            guard let display = chosenDisplay else { return nil }
            return CaptureSource(kind: .display, display: display)
        case .window:
            guard let window = chosenWindow else { return nil }
            let display = displays.first { $0.frame.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) } ?? displays.first
            return display.map { CaptureSource(kind: .window, display: $0, window: window) }
        case .area:
            guard let area,
                  let display = displays.first(where: { $0.frame.contains(CGPoint(x: area.midX, y: area.midY)) }) else { return nil }
            let local = area.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            return CaptureSource(kind: .area, display: display, area: local)
        }
    }

    // MARK: Devices

    /// Runs the mic and camera sessions while the panel or a recording needs them.
    func updateDevices() {
        let active = state != .idle && state != .saving
        let devices = Devices.shared
        if active, micOn, Permissions.shared.microphone == .allowed, let id = devices.microphoneID {
            if mic == nil { mic = DeviceCapture(media: .audio, deviceID: id); mic?.start() }
        } else {
            mic?.stop(); mic = nil
        }
        if active, cameraOn, Permissions.shared.camera == .allowed, let id = devices.cameraID {
            if camera == nil { camera = DeviceCapture(media: .video, deviceID: id); camera?.start() }
            CameraBubble.shared.show(session: camera?.session, near: chosenDisplay)
        } else {
            camera?.stop(); camera = nil
            CameraBubble.shared.hide()
        }
        if let mic {
            meter.start { mic.level }
        } else {
            meter.stop()
        }
    }

    /// Picks a new device: restarts its session.
    func deviceChanged(_ media: DeviceCapture.Media) {
        switch media {
        case .audio: mic?.stop(); mic = nil
        case .video: camera?.stop(); camera = nil
        }
        updateDevices()
    }

    // MARK: Recording

    func start() {
        guard state == .panel, startBlocker == nil, let source = resolveSource() else { return }
        self.source = source
        RecordPanel.shared.hide()
        AreaSelector.shared.hideOverlay()
        state = .countdown
        problem = nil
        Task { await prepareAndCountDown(source) }
    }

    private func prepareAndCountDown(_ source: CaptureSource) async {
        let id = UUID()
        projectID = id
        let timeline = Timeline()
        self.timeline = timeline
        do {
            try ProjectStore.makeFolder(for: id)
            let size = source.pixelSize
            let bitrate = max(8_000_000, size.width * size.height * 4)
            let screenWriter = try TrackWriter(url: ProjectStore.file(ProjectFiles.screen, of: id),
                                               kind: .video(width: size.width, height: size.height, bitrate: bitrate),
                                               timeline: timeline)
            let systemWriter = systemAudioOn ? try TrackWriter(url: ProjectStore.file(ProjectFiles.systemAudio, of: id),
                                                               kind: .audio(channels: 2, bitrate: 192_000), timeline: timeline) : nil
            var all = [screenWriter] + [systemWriter].compactMap { $0 }
            if let mic {
                let writer = try TrackWriter(url: ProjectStore.file(ProjectFiles.microphone, of: id),
                                             kind: .audio(channels: 1, bitrate: 128_000), timeline: timeline)
                mic.setSink { [mic] buffer in writer.append(buffer, host: mic.hostSeconds(buffer)) }
                all.append(writer)
            }
            if let camera {
                let d = camera.dimensions
                let writer = try TrackWriter(url: ProjectStore.file(ProjectFiles.camera, of: id),
                                             kind: .video(width: Int(d.width), height: Int(d.height), bitrate: 6_000_000),
                                             timeline: timeline)
                camera.setSink { [camera] buffer in writer.append(buffer, host: camera.hostSeconds(buffer)) }
                all.append(writer)
            }
            writers = all
            let capture = ScreenCapture(screenWriter: screenWriter, audioWriter: systemWriter) { @Sendable error in
                Task { @MainActor in RecordController.shared.captureFailed(error) }
            }
            screen = capture
            try await capture.start(source: source, excluding: app)
        } catch {
            fail("Unable to start recording: \(error.localizedDescription)")
            return
        }

        Countdown.shared.show(on: source.display.displayID)
        countdownTask = Task {
            for n in stride(from: 3, through: 1, by: -1) {
                countdown = n
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            beginRecording()
        }
    }

    private func beginRecording() {
        guard state == .countdown, let timeline, let source else { return }
        Countdown.shared.hide()
        timeline.begin()
        writers.forEach { $0.primeFirstFrame() }
        let events = EventRecorder(source: source.globalRect, timeline: timeline)
        events.start()
        self.events = events
        CameraBubble.shared.recorder = events
        if let center = CameraBubble.shared.center { events.bubbleMoved(to: center) }
        cameraHidden = false
        state = .recording
        RecordingControls.shared.show(on: source.display.displayID)
        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { RecordController.shared.refreshElapsed() }
        }
        StatusItem.shared.update()
    }

    private func refreshElapsed() {
        elapsed = timeline?.elapsed() ?? 0
        let free = (try? ProjectStore.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? .max
        lowDisk = free < 2_000_000_000
    }

    /// `reason` says what cancelled it ("click", "Escape", "shortcut"); a
    /// self-test run prints it, since a stray click on the real screen cancels too.
    func cancelCountdown(reason: String = "shortcut") {
        guard state == .countdown else { return }
        if SelfTest.requested { print("INFO Countdown cancelled by \(reason)") }
        countdownTask?.cancel()
        Countdown.shared.hide()
        Task {
            await discardRecording()
            state = .idle
            newRecording()
        }
    }

    func togglePause() {
        guard let timeline else { return }
        switch state {
        case .recording: timeline.pause(); state = .paused
        case .paused: timeline.resume(); state = .recording
        default: return
        }
        refreshElapsed()
        StatusItem.shared.update()
    }

    func toggleCameraHidden() {
        guard cameraOn else { return }
        cameraHidden.toggle()
        CameraBubble.shared.setHidden(cameraHidden)
        events?.cameraHidden(cameraHidden)
    }

    /// Stop: saves every track and opens the project.
    func stop() {
        guard isCapturing, let timeline, let id = projectID, let source else { return }
        let end = timeline.elapsed()
        tick?.invalidate(); tick = nil
        RecordingControls.shared.hide()
        state = .saving
        elapsed = end
        StatusItem.shared.update()

        let log = events?.stop(at: end)
        let project = AppServices.shared.model?.addProject(title: Self.defaultTitle(), duration: end, uuid: id)
        project?.isSaving = true
        project?.sourceKind = source.kind.rawValue
        project?.sourceName = source.name
        project?.videoWidth = source.pixelSize.width
        project?.videoHeight = source.pixelSize.height
        if let last = log?.bubble.last { project?.bubbleX = last.x; project?.bubbleY = last.y }
        project?.bubbleSize = BubbleStyle.shared.size
        project?.bubbleShape = BubbleStyle.shared.shape.rawValue

        Task {
            await screen?.stop()
            mic?.setSink(nil)
            camera?.setSink(nil)
            var saved: [URL: Bool] = [:]
            for writer in writers { saved[writer.url] = await writer.finish(at: end) }
            if let log, let data = try? log.encoded() {
                try? data.write(to: ProjectStore.file(ProjectFiles.events, of: id))
            }
            await ProjectStore.makeThumbnail(for: id)
            if let project {
                project.hasMicrophone = saved[ProjectStore.file(ProjectFiles.microphone, of: id)] == true
                project.hasCamera = saved[ProjectStore.file(ProjectFiles.camera, of: id)] == true
                project.hasSystemAudio = saved[ProjectStore.file(ProjectFiles.systemAudio, of: id)] == true
                project.isSaving = false
                try? AppServices.shared.model?.context.save()
            }
            reset()
            AppServices.shared.openProject(id)
        }
    }

    /// Restart: throws this recording away (to the Trash) and counts down again.
    func restart() {
        guard isCapturing, let source else { return }
        tick?.invalidate(); tick = nil
        RecordingControls.shared.hide()
        _ = events?.stop(at: 0)
        state = .countdown
        Task {
            await discardRecording()
            self.source = source
            await prepareAndCountDown(source)
        }
    }

    private func discardRecording() async {
        await screen?.stop()
        mic?.setSink(nil)
        camera?.setSink(nil)
        writers.forEach { $0.cancel() }
        if let id = projectID {
            ProjectStore.trash(ProjectStore.folder(for: id))
        }
        writers = []
        screen = nil
        events = nil
        timeline = nil
        projectID = nil
    }

    private func captureFailed(_ error: Error) {
        if isCapturing {
            problem = "Recording stopped: \(error.localizedDescription). What was recorded up to \(TimeText.clock(elapsed)) is saved."
            stop()
        } else if state == .countdown {
            fail("Unable to start recording: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        countdownTask?.cancel()
        Countdown.shared.hide()
        Task {
            await discardRecording()
            state = .idle
            newRecording()
            problem = message
        }
    }

    private func reset() {
        writers = []
        screen = nil
        events = nil
        timeline = nil
        projectID = nil
        source = nil
        CameraBubble.shared.recorder = nil
        cameraHidden = false
        state = .idle
        elapsed = 0
        updateDevices()
        StatusItem.shared.update()
    }

    /// Snapshot mode only: puts the panels in a sample state without recording.
    func snapshotState(_ state: State, elapsed: Double = 0, countdown: Int = 3) {
        guard Snapshot.isActive else { return }
        self.state = state
        self.elapsed = elapsed
        self.countdown = countdown
    }

    /// Opens the source popover (the chevron sets it too; snapshot mode uses it).
    var showingSourcePicker = false

    static func defaultTitle(at date: Date = .now) -> String {
        "Recording \(date.formatted(.dateTime.month(.abbreviated).day())) at \(date.formatted(date: .omitted, time: .shortened))"
    }
}
