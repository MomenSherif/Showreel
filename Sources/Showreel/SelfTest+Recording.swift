import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftData
import SwiftUI
import ShowreelEngine
import ShowreelKit

/// Self-test checks for recording, from a raw capture to a saved project (M1).
extension SelfTest {
    /// S-007: a real 2.5 s capture of the main display with a pause in the
    /// middle. Needs Screen Recording for the process that started the test.
    static func recording() async {
        guard CGPreflightScreenCaptureAccess() else {
            print("SKIP recording checks: no Screen Recording access for this process")
            return
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
            check("lists the main display", false)
            return
        }
        let id = UUID()
        _ = try? ProjectStore.makeFolder(for: id)
        let timeline = Timeline()
        let source = CaptureSource(kind: .display, display: display)
        let size = source.pixelSize
        do {
            let writer = try TrackWriter(url: ProjectStore.file(ProjectFiles.screen, of: id),
                                         kind: .video(width: size.width, height: size.height, bitrate: 8_000_000),
                                         timeline: timeline)
            let capture = ScreenCapture(screenWriter: writer, audioWriter: nil) { @Sendable _ in }
            let me = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            try await capture.start(source: source, excluding: me)
            try? await Task.sleep(for: .seconds(0.5))
            timeline.begin()
            writer.primeFirstFrame()
            let events = EventRecorder(source: source.globalRect, timeline: timeline)
            events.start()
            try? await Task.sleep(for: .seconds(1.5))
            timeline.pause()
            try? await Task.sleep(for: .seconds(1))
            timeline.resume()
            try? await Task.sleep(for: .seconds(1))
            let end = timeline.elapsed()
            let log = events.stop(at: end)
            await capture.stop()
            let saved = await writer.finish(at: end)
            check("the screen track is saved", saved)
            let stats = writer.stats
            check("the screen writer drops no frames", stats.dropped == 0 && stats.late == 0 && stats.appended > 0, "\(stats)")
            check("the pause leaves no gap in recording time", abs(end - 2.5) < 0.15, "elapsed \(end)")
            let asset = AVURLAsset(url: ProjectStore.file(ProjectFiles.screen, of: id))
            let duration = (try? await asset.load(.duration))?.seconds ?? 0
            check("screen.mov is as long as the recording", abs(duration - end) < 0.2, "file \(duration) vs \(end)")
            let track = try? await asset.loadTracks(withMediaType: .video).first
            let natural = (try? await track?.load(.naturalSize)) ?? .zero
            check("screen.mov has the display's pixel size", Int(natural.width) == size.width, "\(natural) vs \(size)")
            check("the event log knows the source", log.source == source.globalRect)
        } catch {
            check("starts a capture", false, error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: ProjectStore.folder(for: id))
    }

    /// S-002 to S-008 end to end: Record Panel, Countdown, 2 s of recording
    /// with system audio, Stop, and the saved project in the store.
    static func endToEnd(_ model: AppModel) async {
        guard CGPreflightScreenCaptureAccess() else { return }
        let recorder = RecordController.shared
        // The app's real preferences are shared with this run: put them all back.
        let saved = (recorder.micOn, recorder.cameraOn, recorder.systemAudioOn, recorder.sourceKind, recorder.displayID)
        let welcome = UserDefaults.standard.object(forKey: "welcome.done")
        defer {
            recorder.micOn = saved.0; recorder.cameraOn = saved.1
            recorder.systemAudioOn = saved.2; recorder.sourceKind = saved.3; recorder.displayID = saved.4
            UserDefaults.standard.set(welcome, forKey: "welcome.done")
        }
        recorder.micOn = false
        recorder.cameraOn = false
        recorder.systemAudioOn = true
        recorder.sourceKind = .display
        let before = Set(all(model).map(\.uuid))
        UserDefaults.standard.set(true, forKey: "welcome.done")
        recorder.newRecording()
        check("New Recording opens the Record Panel", recorder.state == .panel && RecordPanel.shared.panel?.isVisible == true)
        await recorder.loadContent()
        recorder.displayID = CGMainDisplayID()
        check("Start Recording is ready", recorder.startBlocker == nil, recorder.startBlocker ?? "")
        recorder.start()
        check("Start shows the Countdown", recorder.state == .countdown)
        // Wait for the Countdown to end, not a fixed time: capture can take a
        // moment to start, and the length check below counts from here.
        for _ in 0..<100 where recorder.state != .recording { try? await Task.sleep(for: .seconds(0.05)) }
        check("recording starts after the Countdown", recorder.state == .recording,
              "state \(recorder.state), problem \(recorder.problem ?? "none")")
        check("the Recording Controls are shown", RecordingControls.shared.panel?.isVisible == true)
        try? await Task.sleep(for: .seconds(2))
        recorder.stop()
        for _ in 0..<40 where recorder.state != .idle { try? await Task.sleep(for: .seconds(0.25)) }
        check("Stop saves and returns to idle", recorder.state == .idle)
        guard let project = all(model).first(where: { !before.contains($0.uuid) }) else {
            check("Stop adds a project", false)
            return
        }
        check("the project is about 2 seconds long", abs(project.duration - 2) < 0.4, "\(project.duration)")
        check("the project is no longer saving", !project.isSaving)
        check("the project has its system audio track", project.hasSystemAudio)
        check("the project has no mic or camera track", !project.hasMicrophone && !project.hasCamera)
        let files = ProjectFiles.all.filter { FileManager.default.fileExists(atPath: ProjectStore.file($0, of: project.uuid).path) }
        check("screen.mov, events.json, and a thumbnail are written",
              [ProjectFiles.screen, ProjectFiles.events, ProjectFiles.thumbnail].allSatisfy(files.contains), files.joined(separator: ", "))
        let log = (try? Data(contentsOf: ProjectStore.file(ProjectFiles.events, of: project.uuid))).flatMap { try? EventLog.decode($0) }
        check("events.json decodes", log != nil)
        await editor(project)
        for window in NSApp.windows where window.title == project.title { window.close() }
        try? FileManager.default.removeItem(at: ProjectStore.folder(for: project.uuid))
        model.context.delete(project)
    }
}
