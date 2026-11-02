import AppKit
import AVFoundation
import ShowreelKit

/// Self-test checks for audio (M7).
extension SelfTest {
    /// S-042: track volumes and Mute Section are saved, undoable, and reach
    /// the player's audio mix.
    static func audio(_ editor: EditorModel) async {
        guard let undo = editor.undoManager, let segment = editor.edits.segments.first else { return }
        let original = editor.audio
        undo.removeAllActions()
        undo.groupsByEvent = false
        defer {
            undo.groupsByEvent = true
            editor.applyAudio(original, named: "Audio")
            editor.selectedSegment = nil
            undo.removeAllActions()
        }
        func step(_ action: () -> Void) {
            undo.beginUndoGrouping()
            action()
            undo.endUndoGrouping()
        }
        var louder = editor.audio
        louder.setVolume(1.5, of: .microphone)
        step { editor.applyAudio(louder, named: "Microphone Volume") }
        check("a track volume is saved", AudioMix.decode(editor.project.audioData).microphone == 1.5)
        undo.undo()
        check("Undo puts the volume back", editor.audio == original)

        editor.selectedSegment = segment.id
        let clip = NSApp.mainMenu?.item(withTitle: "Clip")?.submenu?.items.map(\.title) ?? []
        check("the Clip menu has Mute Section", clip.contains("Mute Section"), clip.joined(separator: ", "))
        // The project may have no audio track; the mute itself is checked either way.
        var mix = editor.audio
        mix.toggleMute(from: segment.start, to: segment.end)
        step { editor.applyAudio(mix, named: "Mute Section") }
        check("Mute Section mutes the selected section", editor.isSelectionMuted
              && AudioMix.decode(editor.project.audioData).muted.count == 1)
        if let sources = editor.sources, !sources.audio.isEmpty, let item = editor.player?.currentItem,
           let composition = item.asset as? AVComposition {
            let levels = sources.audioLevels(for: composition, edits: editor.edits, mix: editor.audio)
            check("the player's audio mix is silent in the muted section",
                  levels.muted.first.map { $0.lowerBound < 0.01 } == true && item.audioMix?.inputParameters.count == sources.audio.count)
        }
        undo.undo()
        check("Undo unmutes the section", !editor.isSelectionMuted)
    }
}

extension SelfTest {
    /// S-043: Reduce Noise makes a clean copy of the mic once, plays it, and
    /// is one undo step. Runs on a new project with a spoken mic track, made
    /// from `recorded`'s screen.
    static func noiseReduction(_ model: AppModel, screenFrom recorded: Project) async {
        let project = model.addProject(title: "Noise test", duration: recorded.duration)
        project.hasMicrophone = true
        project.videoWidth = recorded.videoWidth
        project.videoHeight = recorded.videoHeight
        _ = try? ProjectStore.makeFolder(for: project.uuid)
        try? FileManager.default.copyItem(at: ProjectStore.file(ProjectFiles.screen, of: recorded.uuid),
                                          to: ProjectStore.file(ProjectFiles.screen, of: project.uuid))
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", ProjectStore.file(ProjectFiles.microphone, of: project.uuid).path, "--data-format=aac",
                         "Testing noise reduction."]
        try? say.run()
        say.waitUntilExit()
        await noiseChecks(on: project)
        // Close the window first, and delete only once it is gone: a view
        // still reading a deleted model crashes.
        for window in NSApp.windows where window.title == project.title { window.close() }
        for _ in 0..<20 where NSApp.windows.contains(where: { $0.title == project.title && $0.isVisible }) {
            try? await Task.sleep(for: .seconds(0.1))
        }
        try? await Task.sleep(for: .seconds(0.5))
        try? FileManager.default.removeItem(at: ProjectStore.folder(for: project.uuid))
        model.context.delete(project)
        try? model.context.save()
    }

    private static func noiseChecks(on project: Project) async {
        AppServices.shared.openProject(project.uuid)
        for _ in 0..<60 where EditorModel.newest?.project.uuid != project.uuid || EditorModel.newest?.player == nil {
            try? await Task.sleep(for: .seconds(0.1))
        }
        guard let editor = EditorModel.newest, editor.project.uuid == project.uuid, let undo = editor.undoManager else {
            check("a project with a mic opens for Reduce Noise", false)
            return
        }
        undo.removeAllActions()
        undo.groupsByEvent = false
        defer { undo.groupsByEvent = true }

        undo.beginUndoGrouping()
        editor.setReducesNoise(true)
        let job = editor.noiseJob
        check("Reduce Noise first makes a clean copy of the mic", job?.isRunning == true)
        await job?.finished()
        undo.endUndoGrouping()
        check("Reduce Noise is on and saved", editor.audio.reducesNoise && AudioMix.decode(project.audioData).reducesNoise,
              job?.failure ?? "")
        check("the clean mic is written next to the original",
              FileManager.default.fileExists(atPath: editor.cleanMicrophoneURL.path)
              && FileManager.default.fileExists(atPath: ProjectStore.file(ProjectFiles.microphone, of: project.uuid).path))
        func playingFile() -> String? {
            guard let composition = editor.player?.currentItem?.asset as? AVComposition else { return nil }
            let track = composition.tracks.first { $0.mediaType == .audio }
            return track?.segments.first { !$0.isEmpty }?.sourceURL?.lastPathComponent
        }
        check("the editor plays the clean mic", playingFile() == ProjectFiles.cleanMicrophone, playingFile() ?? "none")
        undo.undo()
        check("Undo turns Reduce Noise off and plays the original",
              !editor.audio.reducesNoise && playingFile() == ProjectFiles.microphone, playingFile() ?? "none")
        // Every undoable change sits in a group: with groupsByEvent off, an
        // ungrouped one raises inside NSUndoManager.
        undo.beginUndoGrouping()
        editor.setReducesNoise(true)
        undo.endUndoGrouping()
        check("turning it on again uses the copy it made", editor.noiseJob == nil && editor.audio.reducesNoise)
    }
}
