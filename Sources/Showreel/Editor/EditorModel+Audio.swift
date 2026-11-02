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
        commitPart(from: old, to: new, named: name, current: { $0.audio }, set: { editor, mix in
            editor.audio = mix
            editor.project.audioData = mix == AudioMix() ? nil : mix.encoded()
        }, refresh: { editor, before in
            if before.reducesNoise != editor.audio.reducesNoise {
                // Another file plays: build the item again, and redraw the mic's waveform.
                editor.rebuildItem(keeping: editor.edits.sourceTime(atEditTime: editor.playhead.time))
                editor.loadWaveforms()
            } else {
                editor.remix()
            }
        })
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
        let files = sources.audio.map { ($0.source, sources.playing($0, reducesNoise: audio.reducesNoise).asset.url) }
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

/// Reduce Noise making the clean mic (S-043): its progress, or why it stopped.
@Observable
final class NoiseJob {
    private(set) var fraction: Double = 0
    private(set) var failure: String?
    @ObservationIgnored fileprivate var task: Task<Void, Never>?

    var isRunning: Bool { failure == nil && task != nil }

    func cancel() { task?.cancel() }

    /// Waits until it ends. For the self-test.
    func finished() async { await task?.value }

    fileprivate func report(_ fraction: Double) { self.fraction = fraction }
    fileprivate func fail(_ text: String) { failure = text }

    /// A job frozen at `fraction`, or failed with `failure`, for snapshot pages.
    static func shown(fraction: Double, failure: String? = nil) -> NoiseJob {
        let job = NoiseJob()
        job.fraction = fraction
        job.failure = failure
        if failure == nil { job.task = Task {} }
        return job
    }
}

/// Reduce Noise (S-043): the mic plays from a copy with the background
/// removed. The copy is made once, the first time it is turned on.
extension EditorModel {
    var cleanMicrophoneURL: URL { ProjectStore.file(ProjectFiles.cleanMicrophone, of: project.uuid) }

    /// The Reduce Noise switch. Turning it on the first time makes the clean
    /// mic first; the switch is one undo step once it is applied.
    func setReducesNoise(_ on: Bool) {
        guard on != audio.reducesNoise, noiseJob?.isRunning != true else { return }
        guard on, sources?.cleanMicrophone == nil else {
            var mix = audio
            mix.reducesNoise = on
            applyAudio(mix, named: on ? "Reduce Noise" : "Turn Off Reduce Noise")
            return
        }
        let job = NoiseJob()
        noiseJob = job
        let input = ProjectStore.file(ProjectFiles.microphone, of: project.uuid), output = cleanMicrophoneURL
        job.task = Task { [weak self, weak job] in
            do {
                try await NoiseReducer.clean(input, to: output) { fraction in
                    Task { @MainActor in job?.report(fraction) }
                }
                try Task.checkCancellation()
                guard let self, let track = await PlayerSources.Track.load(output, .audio) else {
                    job?.fail("Unable to read the cleaned microphone recording.")
                    return
                }
                sources?.cleanMicrophone = track
                if noiseJob === job { noiseJob = nil }
                var mix = audio
                mix.reducesNoise = true
                applyAudio(mix, named: "Reduce Noise")
            } catch is CancellationError {
                if self?.noiseJob === job { self?.noiseJob = nil }
            } catch NoiseReducer.Failure.unavailable {
                job?.fail("Reduce Noise isn’t available on this Mac.")
            } catch {
                if Task.isCancelled {
                    if self?.noiseJob === job { self?.noiseJob = nil }
                } else {
                    job?.fail("Unable to reduce noise. \(error.localizedDescription)")
                }
            }
        }
    }
}
