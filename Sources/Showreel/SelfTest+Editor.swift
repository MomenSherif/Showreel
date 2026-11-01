import AppKit
import CoreImage
import AVFoundation
import ScreenCaptureKit
import SwiftData
import SwiftUI
import ShowreelEngine
import ShowreelKit

/// Self-test checks for the Editor (M3).
extension SelfTest {
    /// S-015: a saved recording opens in the Editor with its real length,
    /// the inspector, and the toolbar.
    static func editor(_ project: Project) async {
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
    static func playback(_ editor: EditorModel) async {
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

        await background(editor)
        await autosave(editor)

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
    static func trim(_ editor: EditorModel) async {
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
    static func undo(_ editor: EditorModel) async {
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

    /// S-021: an edit is in the store within a second, and the Editor opens
    /// with it after closing.
    static func autosave(_ editor: EditorModel) async {
        let project = editor.project
        let id = project.uuid
        let source = editor.edits.sourceDuration
        editor.seek(to: 0.6)
        await editor.seeksSettled()
        editor.splitAtPlayhead()
        let saved = editor.edits
        try? await Task.sleep(for: .seconds(1))
        // A second, separate database stack reads what is on disk, as a
        // relaunch after a crash would.
        let onDisk: EditList? = {
            guard let container = try? ModelContainer(for: Project.self, configurations: ModelConfiguration(url: Store.url)) else { return nil }
            let context = ModelContext(container)
            let stored = try? context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.uuid == id })).first
            return stored.map { EditList.decode($0.editsData, sourceDuration: source) }
        }()
        check("an edit is saved to disk within 1 second", onDisk == saved, "\(onDisk?.segments.count ?? -1) segments on disk")
        for window in NSApp.windows where window.title == project.title { window.close() }
        try? await Task.sleep(for: .seconds(0.5))
        AppServices.shared.openProject(id)
        for _ in 0..<60 where !(EditorModel.newest !== editor && EditorModel.newest?.project.uuid == id && EditorModel.newest?.player != nil) {
            try? await Task.sleep(for: .seconds(0.1))
        }
        let reopened = EditorModel.newest
        check("the Editor reopens with the edit", reopened !== editor && reopened?.edits == saved,
              "\(reopened?.edits.segments.count ?? -1) segments")
    }

    /// S-022: a background is saved, is one undo step, shows in the padding,
    /// and a picked image is copied into the project.
    static func background(_ editor: EditorModel) async {
        guard let undo = editor.undoManager else { return }
        undo.removeAllActions()
        undo.groupsByEvent = false
        defer { undo.groupsByEvent = true }
        let before = editor.style
        var red = editor.style
        red.background = .color(RGB(1, 0, 0))
        red.padding = 0.1
        undo.beginUndoGrouping()
        editor.applyStyle(red, named: "Background Color")
        undo.endUndoGrouping()
        check("a background is saved with the project", Style.decode(editor.project.styleData) == red)
        let screen = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 100))
        let frame = Renderer.frame(screen: screen, camera: nil, at: 0, scene: BubbleScene(bubble: [], fallbackCenter: .zero, hidden: [], diameter: 0),
                                   style: editor.renderStyle(for: editor.style), size: CGSize(width: 320, height: 200))
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(frame, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 2, y: 2, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        check("the padding shows the background", pixel[0] > 250 && pixel[1] < 5 && pixel[2] < 5, "\(pixel)")
        undo.undo()
        check("choosing a background is one undo step", editor.style == before)
        // S-023: a Padding drag sends many values and is one undo step.
        undo.beginUndoGrouping()
        let start = editor.style
        for step in 1...12 {
            var dragged = editor.style
            dragged.padding = Double(step) * 0.02
            editor.previewStyle(dragged)
        }
        editor.commitStyle(from: start, named: "Padding")
        undo.endUndoGrouping()
        check("a Padding drag lands on its last value and is saved",
              editor.style.padding == 0.24 && Style.decode(editor.project.styleData).padding == 0.24)
        undo.undo()
        check("one Undo reverts the whole Padding drag", editor.style.padding == before.padding, "\(editor.style.padding)")
        // Back to grouping by event: registering undo outside a group with it
        // off leaves NSUndoManager broken (it crashed SwiftUI later).
        undo.groupsByEvent = true

        // A picked image is copied into the project folder.
        let picked = FileManager.default.temporaryDirectory.appending(path: "showreel-bg-\(UUID().uuidString).png")
        if let ctx = CGContext(data: nil, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0.6, blue: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
            if let cg = ctx.makeImage(), let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: picked)
            }
        }
        editor.chooseBackgroundImage(picked)
        if case .image(let name) = editor.style.background {
            check("a chosen image is copied into the project",
                  FileManager.default.fileExists(atPath: ProjectStore.file(name, of: editor.project.uuid).path))
            check("the chosen image is loaded for drawing", editor.renderStyle(for: editor.style).backgroundImage != nil)
        } else {
            check("a chosen image becomes the background", false, "\(editor.style.background)")
        }
        try? FileManager.default.removeItem(at: picked)
        editor.applyStyle(before, named: "Reset")
        undo.removeAllActions()
    }
}
