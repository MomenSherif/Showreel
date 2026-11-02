import SwiftUI
import ShowreelKit

/// The selected blur in the inspector (S-049): Style, Strength, Timing, and
/// Delete. Done or Esc goes back to the section.
struct BlurInspector: View {
    let editor: EditorModel
    let blur: BlurRegion
    @State private var dragStart: BlurTrack?

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: styleBinding) {
                    ForEach(BlurRegion.Style.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text("Strength")
                        Spacer()
                        Text(StyleSlider.percent(blur.strength))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: strengthBinding, in: 0...1, onEditingChanged: { editing in
                        if editing {
                            dragStart = editor.blurs
                        } else if let start = dragStart {
                            editor.commitBlurs(from: start, named: "Blur Strength")
                            dragStart = nil
                        }
                    })
                    .labelsHidden()
                    .accessibilityLabel("Strength")
                    .accessibilityValue(StyleSlider.percent(blur.strength))
                }
            } footer: {
                Text("Drag on the preview to draw where the blur goes. It stays on the same spot of the screen when you zoom or crop.")
                    .foregroundStyle(.secondary)
            }
            Section("Timing") {
                LabeledContent("Starts", value: editor.editStart(of: blur).map(TimeText.precise) ?? "Cut")
                LabeledContent("Length", value: ClipBlock.length(blur.length))
            }
            Section {
                Button("Delete Blur", role: .destructive) { editor.deleteSelectedBlur() }
                    .help("Delete Blur (⌫)")
            }
        }
        .formStyle(.grouped)
    }

    private var styleBinding: Binding<BlurRegion.Style> {
        Binding(get: { blur.style }, set: { style in
            editor.applyBlurs(editor.blurs.changing(blur.id) { $0.style = style }, named: "Blur Style")
        })
    }

    private var strengthBinding: Binding<Double> {
        Binding(get: { blur.strength }, set: { value in
            let track = editor.blurs.changing(blur.id) { $0.strength = (value * 100).rounded() / 100 }
            // Arrow keys and VoiceOver change the value without a drag: each is its own step.
            if dragStart == nil {
                editor.applyBlurs(track, named: "Blur Strength")
            } else {
                editor.previewBlurs(track)
            }
        })
    }
}
