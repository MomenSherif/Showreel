import AVFoundation
import ShowreelEngine
import ShowreelKit

/// Track volumes and muted sections (S-042): the same undo and save path as
/// the style. A change swaps only the item's audio mix, so a slider drag is
/// heard at once.
extension EditorModel {
    /// Replaces the mix as one undoable step called `name`, and saves it.
    func applyAudio(_ new: AudioMix, named name: String) {
        commitAudio(from: audio, to: new, named: name)
    }

    /// Plays `new` without an undo step or a save, while dragging.
    func previewAudio(_ new: AudioMix) {
        guard new != audio else { return }
        audio = new
        remix()
    }

    /// Ends a drag that started at `old`: one undo step for the whole drag.
    func commitAudio(from old: AudioMix, named name: String) {
        commitAudio(from: old, to: audio, named: name)
    }

    private func commitAudio(from old: AudioMix, to new: AudioMix, named name: String) {
        guard old != new else { return }
        undoManager?.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated { editor.commitAudio(from: editor.audio, to: old, named: name) }
        }
        undoManager?.setActionName(name)
        audio = new
        project.audioData = new == AudioMix() ? nil : new.encoded()
        try? project.modelContext?.save()
        remix()
        refreshUndo()
    }

    /// Swaps the audio mix on the current item.
    func remix() {
        guard let sources, let item = player?.currentItem else { return }
        guard let composition = item.asset as? AVComposition else { return }
        item.audioMix = sources.audioLevels(for: composition, edits: edits, mix: audio).audioMix()
    }

    // MARK: Mute Section

    /// The selected section's source range, for Mute Section.
    private var selectedRange: (start: Double, end: Double)? {
        guard let id = selectedSegment, let segment = edits.segments.first(where: { $0.id == id }) else { return nil }
        return (segment.start, segment.end)
    }

    var canMuteSelection: Bool { selectedRange != nil && !(sources?.audio.isEmpty ?? true) }

    /// True when the selected section is muted all the way through.
    var isSelectionMuted: Bool {
        selectedRange.map { audio.isMuted(from: $0.start, to: $0.end) } ?? false
    }

    /// Clip > Mute Section (M): mutes the selected section, or unmutes it.
    func toggleMuteSelection() {
        guard let range = selectedRange else { return }
        let wasMuted = isSelectionMuted
        var mix = audio
        mix.toggleMute(from: range.start, to: range.end)
        applyAudio(mix, named: wasMuted ? "Unmute Section" : "Mute Section")
    }

    func unmuteAll() {
        var mix = audio
        mix.unmuteAll()
        applyAudio(mix, named: "Unmute All")
    }

    /// Reads each recorded track's loudness off the main thread.
    func loadWaveforms() {
        guard let sources else { return }
        let files = sources.audio.map { ($0.source, $0.track.asset.url) }
        Task {
            for (source, url) in files {
                if let wave = await WaveformReader.read(url) { waveforms[source] = wave }
            }
        }
    }

    /// The loudest peak of the tracks from `start` to `end` (source time),
    /// at their volumes, 0...1.
    nonisolated static func loudness(of waves: [AudioSource: Waveform], mix: AudioMix, from start: Double, to end: Double) -> Float {
        waves.map { source, wave in wave.peak(from: start, to: end) * Float(mix.volume(of: source)) }.max().map { min($0, 1) } ?? 0
    }
}
