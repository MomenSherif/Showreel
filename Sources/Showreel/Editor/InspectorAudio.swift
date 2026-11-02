import SwiftUI
import ShowreelKit

/// The Audio section (S-042): a volume per recorded track, and the muted sections.
struct AudioSection: View {
    let editor: EditorModel

    private var project: Project { editor.project }

    var body: some View {
        Form {
            Section("Volume") {
                if project.hasMicrophone {
                    VolumeSlider(title: "Microphone", source: .microphone, editor: editor)
                    NoiseRow(editor: editor)
                }
                if project.hasSystemAudio {
                    VolumeSlider(title: "System Audio", source: .systemAudio, editor: editor)
                }
            }
            Section {
                LabeledContent("Muted Sections", value: "\(editor.audio.muted.count)")
                if !editor.audio.muted.isEmpty {
                    HStack {
                        Spacer()
                        Button("Unmute All") { editor.unmuteAll() }
                            .help("Play the audio everywhere again")
                    }
                }
            } header: {
                Text("Mute")
            } footer: {
                Text("Select a section on the timeline and press M to mute it. Split first to mute part of the video.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Reduce Noise (S-043): a switch, its progress the first time, or why it failed.
private struct NoiseRow: View {
    let editor: EditorModel

    var body: some View {
        if let job = editor.noiseJob, job.isRunning {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Reducing noise in your voice…")
                HStack(spacing: Space.md) {
                    ProgressView(value: job.fraction)
                        .accessibilityLabel("Reducing noise")
                    Button("Cancel") { job.cancel() }
                        .controlSize(.small)
                        .help("Stop reducing noise")
                }
            }
        } else {
            Toggle(isOn: Binding(get: { editor.audio.reducesNoise }, set: { editor.setReducesNoise($0) })) {
                Text("Reduce Noise")
                Text(editor.noiseJob?.failure ?? "Removes fan hum and room noise from your voice, on this Mac.")
                    .foregroundStyle(.secondary)
            }
            .help("Remove background noise from the microphone")
        }
    }
}

/// One track's volume, 0 to 200%. The whole drag is one undo step.
private struct VolumeSlider: View {
    let title: String
    let source: AudioSource
    let editor: EditorModel
    @State private var dragStart: AudioMix?

    private var text: String { StyleSlider.percent(editor.audio.volume(of: source)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(title)
                Spacer()
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Space.sm) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                Slider(value: binding, in: AudioMix.volumeRange) { editing in
                    if editing {
                        dragStart = editor.audio
                    } else if let start = dragStart {
                        editor.commitAudio(from: start, named: "\(title) Volume")
                        dragStart = nil
                    }
                }
                .labelsHidden()
                .accessibilityLabel("\(title) volume")
                .accessibilityValue(text)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
    }

    private var binding: Binding<Double> {
        Binding(get: { editor.audio.volume(of: source) }, set: { value in
            var mix = editor.audio
            mix.setVolume(value, of: source)
            // Arrow keys and VoiceOver change it without a drag: one step each.
            if dragStart == nil {
                editor.applyAudio(mix, named: "\(title) Volume")
            } else {
                editor.previewAudio(mix)
            }
        })
    }
}
