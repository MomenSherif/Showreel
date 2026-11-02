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
