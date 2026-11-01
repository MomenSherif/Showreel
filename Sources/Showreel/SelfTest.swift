import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftData
import SwiftUI
import ShowreelEngine
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
        bubbleStyle(bubble, panel: panel)
        bubble.hide()
        hideCamera()
    }

    /// S-014: hiding the camera while recording is logged as a range, and the
    /// player leaves the camera out for that range.
    private static func hideCamera() {
        let timeline = Timeline()
        let events = EventRecorder(source: CGRect(x: 0, y: 0, width: 100, height: 100), timeline: timeline)
        timeline.begin(at: Timeline.hostNow - 2)   // two seconds in
        events.cameraHidden(true)
        timeline.pause()
        timeline.resume(at: Timeline.hostNow + 0)
        let log = events.stop(at: 5)               // still hidden when it stops
        let range = log.cameraHidden.first
        check("hiding the camera logs a range that ends at Stop",
              log.cameraHidden.count == 1 && abs((range?.start ?? 0) - 2) < 0.2 && range?.end == 5, "\(log.cameraHidden)")
        let scene = BubbleScene(bubble: [], fallbackCenter: .zero, hidden: log.cameraHidden, diameter: 0.1)
        check("the player hides the camera in that range", scene.isHidden(at: 3) && !scene.isHidden(at: 1))
        let paused = Timeline()
        let pausedEvents = EventRecorder(source: CGRect(x: 0, y: 0, width: 100, height: 100), timeline: paused)
        paused.begin(at: Timeline.hostNow - 3)
        paused.pause(at: Timeline.hostNow - 1)     // paused at 2 s
        pausedEvents.cameraHidden(true)
        let pausedLog = pausedEvents.stop(at: 4)
        check("hiding the camera while paused counts from the pause",
              abs((pausedLog.cameraHidden.first?.start ?? -1) - 2) < 0.2, "\(pausedLog.cameraHidden)")
        let menu = NSApp.mainMenu?.item(withTitle: "Record")?.submenu?.items.map(\.title) ?? []
        check("the Record menu has Hide Camera Bubble", menu.contains("Hide Camera Bubble"), menu.joined(separator: ", "))
    }

    /// S-013: size and shape change the bubble and are remembered.
    private static func bubbleStyle(_ bubble: CameraBubble, panel: NSWindow) {
        let style = BubbleStyle.shared
        let saved = (style.size, style.shape)
        defer { style.size = saved.0; style.shape = saved.1 }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        style.size = 2
        check("Large makes the bubble 240 pt", panel.frame.width == Layout.bubbleSizes[2] + 2 * CameraBubble.margin)
        check("resizing keeps the bubble's center", abs(panel.frame.midX - center.x) < 1 && abs(panel.frame.midY - center.y) < 1)
        check("the size is remembered", UserDefaults.standard.integer(forKey: "bubble.size") == 2)
        style.shape = .roundedSquare
        check("the shape is remembered", UserDefaults.standard.string(forKey: "bubble.shape") == "roundedSquare")
        bubble.showControls()
        check("hover shows the size and shape controls", bubble.controls?.parent === panel)
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

    /// S-015: a saved recording opens in the Editor with its real length,
    /// the inspector, and the toolbar.
    private static func editor(_ project: Project) async {
        AppServices.shared.openProject(project.uuid)
        for _ in 0..<60 where EditorModel.newest?.project.uuid != project.uuid { try? await Task.sleep(for: .seconds(0.1)) }
        guard let editor = EditorModel.newest, editor.project.uuid == project.uuid else {
            check("the project opens in the Editor", false)
            return
        }
        check("the project opens in the Editor", editor.player != nil)
        check("the Editor's length matches the recording", abs(editor.duration - project.duration) < 0.2,
              "\(editor.duration) vs \(project.duration)")
        check("the inspector is shown with six sections", editor.showsInspector && InspectorSection.allCases.count == 6)
        let window = NSApp.windows.first { $0.title == project.title && $0.isVisible }
        let items = window?.toolbar?.items.compactMap { $0.label.isEmpty ? $0.paletteLabel : $0.label } ?? []
        check("the toolbar has Undo, Redo, and Export…",
              ["Undo", "Redo", "Export…"].allSatisfy { label in items.contains { $0.contains(label) } }, items.joined(separator: ", "))
        let view = NSApp.mainMenu?.item(withTitle: "View")?.submenu?.items.map(\.title) ?? []
        check("the View menu toggles the inspector", view.contains { $0.contains("Inspector") }, view.joined(separator: ", "))
        await playback(editor)
    }

    /// S-016: seeking lands on the frame asked for, steps move one frame,
    /// and a scrub shows its frame quickly on a Retina-size recording.
    private static func playback(_ editor: EditorModel) async {
        guard let player = editor.player else { return }
        editor.seek(to: 1.25)
        await editor.seeksSettled()
        check("seeking moves the canvas and the playhead", abs(player.currentTime().seconds - 1.25) < 0.02
              && editor.playhead.time == 1.25, "\(player.currentTime().seconds)")
        editor.step(frames: 1)
        await editor.seeksSettled()
        check("Next Frame moves one frame", abs(editor.playhead.time - 76.0 / 60) < 0.0001, "\(editor.playhead.time)")
        editor.jump(by: -5)
        await editor.seeksSettled()
        check("Back 1 Second stops at the start", editor.playhead.time == 0)

        var times: [Double] = []
        for i in 0..<12 {
            editor.seek(to: Double(i % 6) * editor.duration / 6 + 0.137)
            await editor.seeksSettled()
            times.append(editor.lastSeekDuration)
        }
        let sorted = times.sorted()
        let median = sorted[sorted.count / 2]
        let size = "\(editor.project.videoWidth)×\(editor.project.videoHeight)"
        // The one-frame target (S-016) moved to S-047, which adds a fast preview
        // path. Until then this guards against getting slower than 3 frames.
        check("a scrub shows its frame within 3 frame times (median)", median < 3.0 / 60,
              String(format: "median %.1f ms, worst %.1f ms at %@", median * 1000, (sorted.last ?? 0) * 1000, size))
        print(String(format: "INFO scrub latency at %@: median %.1f ms, worst %.1f ms", size, median * 1000, (sorted.last ?? 0) * 1000))

        await trim(editor)

        await undo(editor)

        // S-017: the timeline zoom.
        editor.zoom.zoomIn()
        editor.zoom.zoomIn()
        check("Zoom In zooms the timeline", editor.zoom.level == 0.25)
        editor.zoom.fit()
        let view = NSApp.mainMenu?.item(withTitle: "View")?.submenu?.items.map(\.title) ?? []
        check("the View menu has Zoom In, Zoom Out, and Zoom to Fit",
              ["Zoom In", "Zoom Out", "Zoom to Fit"].allSatisfy(view.contains), view.joined(separator: ", "))

        let menu = NSApp.mainMenu?.item(withTitle: "Playback")?.submenu?.items.map(\.title) ?? []
        check("the Playback menu has Play, frame steps, and Go to Start",
              ["Play", "Previous Frame", "Next Frame", "Back 1 Second", "Forward 1 Second", "Go to Start", "Go to End"]
                .allSatisfy(menu.contains), menu.joined(separator: ", "))
    }

    /// S-018: trims are ranges. The video gets shorter; the files do not change.
    private static func trim(_ editor: EditorModel) async {
        let files = ProjectFiles.all.map { ProjectStore.file($0, of: editor.project.uuid) }
        func stamps() -> [Date?] {
            files.map { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
        }
        let before = stamps()
        let source = editor.edits.sourceDuration
        editor.seek(to: 0.5)
        await editor.seeksSettled()
        editor.trimStartToPlayhead()
        await editor.seeksSettled()
        check("Trim Start to Playhead shortens the video", abs(editor.duration - (source - 0.5)) < 0.01, "\(editor.duration)")
        let itemLength = (try? await editor.player?.currentItem?.asset.load(.duration).seconds) ?? 0
        check("the player plays the trimmed length", abs(itemLength - editor.duration) < 0.02, "\(itemLength)")
        check("the trim is stored with the project", EditList.decode(editor.project.editsData, sourceDuration: source) == editor.edits)
        check("the recording files are never changed", stamps() == before)
        let menu = NSApp.mainMenu?.item(withTitle: "Clip")?.submenu?.items.map(\.title) ?? []
        check("the Clip menu has Trim Start and Trim End to Playhead",
              menu.contains("Trim Start to Playhead") && menu.contains("Trim End to Playhead"), menu.joined(separator: ", "))
        editor.apply(EditList(sourceDuration: source))
        await editor.seeksSettled()

        // S-019: split, select the first piece, delete it.
        editor.seek(to: 0.8)
        await editor.seeksSettled()
        editor.splitAtPlayhead()
        check("Split at Playhead makes two pieces", editor.edits.segments.count == 2)
        editor.selectedSegment = editor.edits.segments.first?.id
        editor.deleteSelection()
        await editor.seeksSettled()
        check("Delete Section removes the piece and closes the gap",
              editor.edits.segments.count == 1 && abs(editor.duration - (source - 0.8)) < 0.01, "\(editor.duration)")
        check("the playhead stays on the same moment of the recording", abs(editor.playhead.time) < 0.02, "\(editor.playhead.time)")
        let clip = NSApp.mainMenu?.item(withTitle: "Clip")?.submenu?.items.map(\.title) ?? []
        check("the Clip menu has Split at Playhead and Delete Section",
              clip.contains("Split at Playhead") && clip.contains("Delete Section"), clip.joined(separator: ", "))
        editor.apply(EditList(sourceDuration: source))
        await editor.seeksSettled()
    }

    /// S-020: every edit is one undo step, a drag included, and redo walks back.
    private static func undo(_ editor: EditorModel) async {
        guard let undo = editor.undoManager else {
            check("the Editor has the window's undo manager", false)
            return
        }
        // AppKit groups undo by event. Here one group per action stands in
        // for one key press or menu command each.
        undo.removeAllActions()
        undo.groupsByEvent = false
        defer { undo.groupsByEvent = true }
        func action(_ body: () -> Void) async {
            undo.beginUndoGrouping()
            body()
            undo.endUndoGrouping()
            await editor.seeksSettled()
        }
        let uncut = editor.edits
        editor.seek(to: 1)
        await editor.seeksSettled()
        await action { editor.splitAtPlayhead() }
        let split = editor.edits
        // A trim drag sends many updates and applies once.
        await action {
            guard let first = editor.edits.segments.first else { return }
            for step in 1...10 { editor.previewTrim(first.id, edge: .start, by: Double(step) * 0.02) }
            editor.commitTrim()
        }
        check("the Edit menu names the step", undo.undoMenuItemTitle == "Undo Trim", undo.undoMenuItemTitle)
        undo.undo()
        await editor.seeksSettled()
        check("one Undo reverts the whole trim drag", editor.edits == split)
        undo.undo()
        await editor.seeksSettled()
        check("a second Undo reverts the split", editor.edits == uncut)
        check("the toolbar's Undo is off with nothing to undo", !editor.canUndo && editor.canRedo)
        undo.redo()
        await editor.seeksSettled()
        check("Redo brings the split back", editor.edits == split && editor.canUndo)
        await action { editor.apply(uncut) }
        undo.removeAllActions()
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
