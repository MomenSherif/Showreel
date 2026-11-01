import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftData
import SwiftUI
import ShowreelKit

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Showreel-self.store ~/Applications/Showreel.app/Contents/MacOS/Showreel --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            projects(model)
            library(model)
            menuBar()
            panels()
            await recording()
            await endToEnd(model)
            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func all(_ model: AppModel) -> [Project] {
        (try? model.context.fetch(FetchDescriptor<Project>())) ?? []
    }

    /// S-008: projects survive in the store with their fields.
    private static func projects(_ model: AppModel) {
        let before = all(model).count
        let project = model.addProject(title: "  Self-test   recording ", duration: 12)
        check("adding a project adds one project", all(model).count == before + 1)
        check("the new project is selected", model.selection == project.uuid)
        check("the project title is cleaned", project.title == "Self-test recording")
        check("an empty title becomes Untitled Project", ProjectTitle.clean("  ") == ProjectTitle.untitled)
        check("a new recording gets a dated title", RecordController.defaultTitle().hasPrefix("Recording "))
        model.context.delete(project)
        try? model.context.save()
    }

    /// S-010: Rename, Duplicate, and Move to Trash, each with Undo.
    private static func library(_ model: AppModel) {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let project = model.addProject(title: "Trash me", duration: 5)
        let id = project.uuid
        _ = try? ProjectStore.makeFolder(for: id)
        FileManager.default.createFile(atPath: ProjectStore.file(ProjectFiles.screen, of: id).path, contents: Data([1, 2, 3]))

        undo.beginUndoGrouping()
        ProjectStore.rename(project, to: "  Renamed  ", undo: undo)
        undo.endUndoGrouping()
        check("rename cleans the title", project.title == "Renamed")
        undo.undo()
        check("undo restores the old title", project.title == "Trash me")

        undo.beginUndoGrouping()
        let copy = ProjectStore.duplicate(project, in: model, undo: undo)
        undo.endUndoGrouping()
        check("duplicate copies the folder",
              FileManager.default.fileExists(atPath: ProjectStore.file(ProjectFiles.screen, of: copy.uuid).path))
        check("duplicate is named copy", copy.title == "Trash me copy")
        ProjectStore.moveToTrash(copy, in: model, undo: nil)

        let before = all(model).count
        undo.beginUndoGrouping()
        ProjectStore.moveToTrash(project, in: model, undo: undo)
        undo.endUndoGrouping()
        check("move to trash removes the card", all(model).count == before - 1 && model.project(id) == nil)
        check("move to trash moves the folder", !FileManager.default.fileExists(atPath: ProjectStore.folder(for: id).path))
        check("undo says Move to Trash", undo.undoActionName == "Move to Trash")
        undo.undo()
        check("undo brings the card back", model.project(id) != nil)
        check("undo brings the folder back",
              FileManager.default.fileExists(atPath: ProjectStore.file(ProjectFiles.screen, of: id).path))
        undo.redo()
        check("redo moves it to the trash again", model.project(id) == nil)
    }

    /// S-002: the menu bar item's menu and the Record menu.
    private static func menuBar() {
        StatusItem.shared.update()
        let titles = StatusItem.shared.itemTitles
        check("menu bar menu has New Recording, Open Library, Settings, Quit",
              ["New Recording", "Open Library", "Settings…", "Quit Showreel"].allSatisfy(titles.contains),
              titles.joined(separator: ", "))
        let mainMenu = NSApp.mainMenu?.items.map(\.title) ?? []
        check("the menu bar has a Record menu", mainMenu.contains("Record"), mainMenu.joined(separator: ", "))
    }

    /// S-011: floating chrome, the Camera Bubble included, never shows up in a recording.
    private static func panels() {
        let panel = FloatingPanel(size: CGSize(width: Space.md, height: Space.md), options: .init(), content: Color.clear)
        check("floating panels are left out of screen capture", panel.sharingType == .none)
        check("floating panels are not in the Window menu", panel.isExcludedFromWindowsMenu)
        check("the Camera Bubble is Medium by default", CameraBubble.shared.diameter == Layout.bubbleSizes[1])
        bubbleSnap()
    }

    /// S-012: a bubble dropped near a corner glides into it; one dropped in
    /// the open stays where it is; moves are logged in source coordinates.
    private static func bubbleSnap() {
        let bubble = CameraBubble.shared
        bubble.show(session: nil, near: nil)
        guard let panel = bubble.panel, let visible = panel.screen?.visibleFrame else {
            check("shows the Camera Bubble", false)
            return
        }
        let side = panel.frame.width
        let inset = Layout.snapDistance - CameraBubble.margin
        panel.setFrameOrigin(NSPoint(x: visible.minX + inset + 15, y: visible.maxY - side - inset - 10))
        bubble.settle(animated: false)
        check("a bubble dropped near the top-left corner snaps into it",
              panel.frame.origin == NSPoint(x: visible.minX + inset, y: visible.maxY - side - inset), "\(panel.frame.origin)")
        let free = NSPoint(x: visible.midX - 200, y: visible.midY - 150)
        panel.setFrameOrigin(free)
        bubble.settle(animated: false)
        check("a bubble dropped in the open stays there", panel.frame.origin == free)

        let timeline = Timeline()
        let source = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let events = EventRecorder(source: source, timeline: timeline)
        timeline.begin(at: Timeline.hostNow - 1)
        events.bubbleMoved(to: CGPoint(x: 250, y: 400))
        let move = events.stop(at: 2).bubble.first
        check("a bubble move is logged in source coordinates with its time",
              move?.x == 0.25 && move?.y == 0.8 && (move?.t ?? 0) >= 1, "\(String(describing: move))")
        bubble.hide()
    }

    /// S-007: a real 2.5 s capture of the main display with a pause in the
    /// middle. Needs Screen Recording for the process that started the test.
    private static func recording() async {
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
    private static func endToEnd(_ model: AppModel) async {
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
        try? await Task.sleep(for: .seconds(3.6))
        check("recording starts after the Countdown", recorder.state == .recording)
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
        for window in NSApp.windows where window.title == project.title { window.close() }
        try? FileManager.default.removeItem(at: ProjectStore.folder(for: project.uuid))
        model.context.delete(project)
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
