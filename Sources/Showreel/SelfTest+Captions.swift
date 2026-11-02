import AppKit
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
        undo.undo()

        // A cancelled run leaves the captions as they were.
        let cancelled = editor.generateCaptions(from: url)
        cancelled?.cancel()
        await cancelled?.finished()
        check("Cancel stops Generate Captions without changing the captions",
              editor.captions == original && editor.captionJob == nil, cancelled?.failure ?? "")
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
}
