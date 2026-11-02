import AppKit
import ShowreelKit

/// Self-test checks for the speech model picker and downloads (S-050, S-051, S-052).
extension SelfTest {
    static func speechModels(_ editor: EditorModel, speech: URL) async {
        let models = SpeechModels.shared
        let real = ModelLocator.standard
        let root = URL(fileURLWithPath: "/tmp/Showreel-selftest-models")
        let own = root.appending(path: "own"), handy = root.appending(path: "handy")
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: handy, withIntermediateDirectories: true)
        let saved = (models.model, models.language, models.locator)
        defer {
            models.locator = saved.2
            models.model = saved.0
            models.language = saved.1
            try? FileManager.default.removeItem(at: root)
        }
        models.locator = ModelLocator(own: own, handy: handy)

        // S-050: Apple by default; the choice is kept and decides the languages.
        check("captions start with Apple's model", saved.0 == .apple, saved.0.rawValue)
        models.model = .whisperTurbo
        check("the speech model is kept", Store.defaults.string(forKey: "captions.model") == "whisperTurbo")
        check("Whisper offers Automatic and Arabic", models.languages.first == CaptionLanguage.automatic && models.languages.contains("ar"))
        models.language = "ar"
        check("a missing model disables Generate Captions", !editor.speechModelIsReady && !editor.canGenerateCaptions)
        models.model = .apple
        check("Apple's model does not offer Arabic", !models.languages.contains("ar") && models.language != "ar", models.language)
        check("Apple's model is built in", models.availability(of: .apple) == .builtIn && editor.speechModelIsReady)

        // S-051: Handy's copy is found and never deleted. A sparse file of the exact size stands in for it.
        let handyFile = handy.appending(path: SpeechModel.whisperSmall.fileName ?? "")
        FileManager.default.createFile(atPath: handyFile.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: handyFile) {
            try? handle.truncate(atOffset: UInt64(SpeechModel.whisperSmall.byteCount ?? 0))
            try? handle.close()
        }
        models.refresh()
        check("a Whisper model in Handy's folder is used from there", models.availability(of: .whisperSmall) == .fromHandy(handyFile))
        models.delete(.whisperSmall)
        check("Delete never touches Handy's copy", FileManager.default.fileExists(atPath: handyFile.path))

        // A download of the wrong size is refused and leaves no file.
        let wrong = root.appending(path: "wrong.bin")
        try? Data(repeating: 7, count: 4096).write(to: wrong)
        models.download(.whisperTurbo, from: wrong)
        await models.downloadsFinished()
        let ownFiles = (try? FileManager.default.contentsOfDirectory(atPath: own.path)) ?? []
        check("a download of the wrong size is refused and leaves no file",
              models.availability(of: .whisperTurbo) == .missing && ownFiles.isEmpty && models.failures[.whisperTurbo] != nil,
              ownFiles.joined(separator: ", "))
        // Cancelled right away: no file, no error.
        models.download(.whisperTurbo)
        check("a download shows its progress", models.downloads[.whisperTurbo] != nil)
        models.cancelDownload(.whisperTurbo)
        await models.downloadsFinished()
        let afterCancel = (try? FileManager.default.contentsOfDirectory(atPath: own.path)) ?? []
        check("a cancelled download leaves no file", afterCancel.isEmpty && models.downloads[.whisperTurbo] == nil
              && models.failures[.whisperTurbo] == nil, afterCancel.joined(separator: ", "))

        // S-052: captions with a real Whisper model, when this Mac has one.
        models.locator = real
        guard let whisper = [SpeechModel.whisperTurbo, .whisperSmall].first(where: { real.availability(of: $0).isReady }) else {
            print("SKIP Whisper captions: no Whisper model on this Mac")
            return
        }
        models.model = whisper
        models.language = CaptionLanguage.automatic
        // The caller turned grouping by event off: an undo step outside a group
        // throws, and an exception through a MainActor job breaks Swift's executor tracking.
        editor.undoManager?.beginUndoGrouping()
        let job = editor.generateCaptions(from: speech)
        await job?.finished()
        editor.undoManager?.endUndoGrouping()
        let lines = editor.captions.captions
        check("\(whisper.title) makes timed captions", lines.count >= 3 && editor.captions.language == "en",
              job?.failure ?? "\(lines.count) lines in \(editor.captions.language)")
        check("Whisper captions keep word timings in order",
              zip(lines, lines.dropFirst()).allSatisfy { $0.end <= $1.start + 0.01 } && lines.allSatisfy { !$0.words.isEmpty })
        editor.undoManager?.undo()
    }
}
