import AppKit
import CoreImage
import ShowreelEngine
import ShowreelKit

/// Self-test checks for captions (M7).
extension SelfTest {
    /// S-039: Generate Captions makes timed lines from speech, on this Mac,
    /// saves them, and is one undo step.
    static func captions(_ editor: EditorModel) async {
        guard let undo = editor.undoManager else { return }
        let original = editor.captions
        undo.removeAllActions()
        undo.groupsByEvent = false
        defer {
            undo.groupsByEvent = true
            editor.applyCaptions(original, named: "Captions")
            undo.removeAllActions()
        }
        let url = URL(fileURLWithPath: "/tmp/Showreel-selftest-speech.m4a")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "--data-format=aac",
                         "Welcome to Showreel. Click the record button to start a new recording, then open it in the editor."]
        try? say.run()
        say.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: url) }

        undo.beginUndoGrouping()
        let job = editor.generateCaptions(from: url)
        check("Generate Captions starts and shows the Captions section", job?.isRunning == true && editor.section == .captions)
        await job?.finished()
        undo.endUndoGrouping()
        let lines = editor.captions.captions
        check("Generate Captions makes timed lines", lines.count >= 3 && editor.captionJob == nil,
              job?.failure ?? "\(lines.count) lines")
        check("caption lines are 42 characters or fewer", lines.allSatisfy { $0.text.count <= CaptionTrack.maxCharacters },
              lines.map(\.text).joined(separator: " | "))
        check("captions keep word timings in order",
              zip(lines, lines.dropFirst()).allSatisfy { $0.end <= $1.start + 0.01 } && lines.allSatisfy { !$0.words.isEmpty })
        check("captions are saved with the project", CaptionTrack.decode(editor.project.captionsData) == editor.captions)
        let clip = NSApp.mainMenu?.item(withTitle: "Clip")?.submenu?.items.map(\.title) ?? []
        check("the Clip menu has Generate Captions", clip.contains("Generate Captions"), clip.joined(separator: ", "))
        check("Undo Generate Captions is offered", undo.undoActionName == "Generate Captions", undo.undoActionName)
        undo.undo()
        check("Undo removes the captions", editor.captions == original)
        undo.redo()
        await captionEditing(editor)
        captionStyle(editor)
        undo.undo()

        // A cancelled run leaves the captions as they were.
        let cancelled = editor.generateCaptions(from: url)
        cancelled?.cancel()
        await cancelled?.finished()
        check("Cancel stops Generate Captions without changing the captions",
              editor.captions == original && editor.captionJob == nil, cancelled?.failure ?? "")
        await speechModels(editor, speech: url)
    }

    /// S-040: a caption's text and timing are edited, each as one undo step,
    /// and captions shift with cuts.
    static func captionEditing(_ editor: EditorModel) async {
        guard let undo = editor.undoManager, let caption = editor.captions.captions.first,
              let duration = editor.sources?.duration else {
            check("captions to edit", false)
            return
        }
        func step(_ action: () -> Void) {
            undo.beginUndoGrouping()
            action()
            undo.endUndoGrouping()
        }
        editor.selectCaption(caption.id, editText: true)
        check("a selected caption shows in the inspector", editor.selectedCaptionItem?.id == caption.id
              && editor.selectedZoom == nil && editor.selectedSegment == nil && editor.editsCaptionText)

        step { editor.setText("Welcome to Showreel, friends.", ofCaption: caption.id) }
        check("editing a caption's text is saved", CaptionTrack.decode(editor.project.captionsData)?.captions.first?.text
              == "Welcome to Showreel, friends.", editor.captions.captions.first?.text ?? "")
        check("Undo Edit Caption is offered", undo.undoActionName == "Edit Caption", undo.undoActionName)
        editor.setText("   ", ofCaption: caption.id)  // no undo step: nothing changes
        check("empty text is not applied", editor.captions.captions.first?.text == "Welcome to Showreel, friends.")
        undo.undo()
        check("Undo puts the text back", editor.captions.captions.first?.text == caption.text)

        // A drag on the end edge: many moves, one undo step.
        let start = editor.captions
        step {
            for i in 1...10 { editor.previewCaptions(start.resizing(caption.id, edge: .end, by: -0.03 * Double(i), duration: duration)) }
            editor.commitCaptions(from: start, named: "Change Caption Timing")
        }
        let shorter = editor.captions.captions.first
        check("dragging a caption's edge changes its timing", abs((shorter?.end ?? 0) - (caption.end - 0.3)) < 0.001
              && shorter?.start == caption.start)
        undo.undo()
        check("one Undo reverts the whole timing drag", editor.captions.captions.first == caption)

        step { editor.deleteSelectedCaption() }
        check("Delete Caption removes it", !editor.captions.captions.contains { $0.id == caption.id } && editor.selectedCaption == nil)
        undo.undo()
        check("Undo brings the caption back", editor.captions.captions.first?.id == caption.id)

        // Captions are in source time: cutting 0.5 s before the second
        // caption moves it 0.5 s earlier in the video.
        guard let second = editor.captions.captions.dropFirst().first, second.start > 1,
              let before = editor.editStart(of: second) else { return }
        let edits = editor.edits
        var cut = edits
        let a = cut.split(atEditTime: second.start - 0.75)
        _ = cut.split(atEditTime: second.start - 0.25)
        if let piece = cut.segments.first(where: { abs($0.start - (second.start - 0.75)) < 0.01 }) { _ = cut.delete(piece.id) }
        step { editor.apply(cut, named: "Delete Section") }
        let after = editor.editStart(of: second)
        check("captions shift with cuts", a != nil && after.map { abs(before - $0 - 0.5) < 0.02 } == true,
              "\(before) -> \(after ?? -1)")
        undo.undo()
        editor.selectCaption(nil)
    }

    /// S-041: the caption style is drawn by the same renderer the export
    /// uses, and each change is one undo step.
    static func captionStyle(_ editor: EditorModel) {
        guard let undo = editor.undoManager, let caption = editor.captions.captions.first else { return }
        let before = editor.style
        let t = caption.start + 0.05
        func frame(_ style: Style) -> [UInt8] {
            let screen = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.8)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 400))
            let image = Renderer.frame(screen: screen, camera: nil, at: t,
                                       scene: BubbleScene(bubble: [], fallbackCenter: .zero, hidden: [], diameter: 0),
                                       style: editor.renderStyle(for: style), size: CGSize(width: 640, height: 400))
            var bytes = [UInt8](repeating: 0, count: 640 * 400 * 4)
            CIContext().render(image, toBitmap: &bytes, rowBytes: 640 * 4, bounds: CGRect(x: 0, y: 0, width: 640, height: 400),
                               format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return bytes
        }
        var hidden = before
        hidden.captions.isVisible = false
        check("captions are drawn in the video", frame(before) != frame(hidden))
        var top = before
        top.captions.position = .top
        undo.beginUndoGrouping()
        editor.applyStyle(top, named: "Caption Position")
        undo.endUndoGrouping()
        check("a caption style change is saved", Style.decode(editor.project.styleData).captions.position == .top)
        check("moving captions to the top changes the frame", frame(editor.style) != frame(before))
        undo.undo()
        check("Undo puts the caption style back", editor.style == before)
        captionLooks(editor, frame: frame)
    }

    /// S-056, S-057: picking a caption style keeps size and position and is
    /// one undo step; a saved style is kept for every project and can be deleted.
    static func captionLooks(_ editor: EditorModel, frame: (Style) -> [UInt8]) {
        guard let undo = editor.undoManager, let pop = CaptionLook.named("bold-pop") else { return }
        let before = editor.style
        var picked = before
        picked.captions.position = .top
        picked.captions.size = 1.3
        undo.beginUndoGrouping()
        editor.applyStyle(picked, named: "Caption Position")
        undo.endUndoGrouping()
        var styled = editor.style
        styled.captions = editor.style.captions.withLook(of: pop.style)
        undo.beginUndoGrouping()
        editor.applyStyle(styled, named: "\(pop.name) Captions")
        undo.endUndoGrouping()
        let saved = Style.decode(editor.project.styleData).captions
        check("picking Bold Pop is saved and keeps the size and position",
              saved.hasLook(of: pop.style) && saved.position == .top && saved.size == 1.3)
        check("Undo Bold Pop Captions is offered", undo.undoActionName == "Bold Pop Captions", undo.undoActionName)
        check("a caption style changes the frame", frame(editor.style) != frame(picked))

        var custom = editor.style
        custom.captions.font = .serif
        custom.captions.outline = 0.3
        custom.captions.textColor = RGB(1, 0.4, 0.2)
        undo.beginUndoGrouping()
        editor.applyStyle(custom, named: "Caption Font")
        undo.endUndoGrouping()
        let looks = CaptionLooks.shared
        check("a changed style is Custom", looks.match(editor.style.captions) == nil)
        let mine = looks.save(editor.style.captions, named: "Self-test style")
        check("a saved caption style is kept in the app's settings",
              SavedCaptionLooks.decode(Store.defaults.data(forKey: "captions.savedStyles")).looks.contains { $0.id == mine.id }
              && looks.match(editor.style.captions)?.id == mine.id)
        looks.delete(mine.id)
        check("Delete Style removes a saved style", !looks.saved.looks.contains { $0.id == mine.id })

        let clip = NSApp.mainMenu?.item(withTitle: "Clip")?.submenu?.items.map(\.title) ?? []
        check("the Clip menu has Save Caption Style…", clip.contains("Save Caption Style…"), clip.joined(separator: ", "))
        undo.undo()
        undo.undo()
        undo.undo()
        check("Undo puts the caption style back after picking styles", editor.style == before)
    }
}
