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

        // A cancelled run leaves the captions as they were.
        let cancelled = editor.generateCaptions(from: url)
        cancelled?.cancel()
        await cancelled?.finished()
        check("Cancel stops Generate Captions without changing the captions",
              editor.captions == original && editor.captionJob == nil, cancelled?.failure ?? "")
    }
}
