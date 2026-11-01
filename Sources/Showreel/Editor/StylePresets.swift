import SwiftData
import SwiftUI
import ShowreelKit

extension EditorModel {
    /// Applies a preset's look as one undo step (S-029); this recording's
    /// crop, camera position, and address stay.
    func applyPreset(_ preset: StylePreset) {
        applyStyle(style.applying(preset: preset.style), named: "Apply Preset “\(preset.name)”")
    }
}

/// Inspector > Background > Preset: apply a saved style, or save this one.
struct PresetSection: View {
    let editor: EditorModel
    @Environment(AppModel.self) private var model
    @Query(sort: \StylePreset.createdAt) private var presets: [StylePreset]

    var body: some View {
        Section("Preset") {
            LabeledContent("Style") {
                HStack(spacing: Space.sm) {
                    Menu("Apply") {
                        if presets.isEmpty {
                            Text("No Presets Yet")
                        }
                        ForEach(presets) { preset in
                            Menu(preset.isDefault ? "\(preset.name) (Default)" : preset.name) {
                                Button("Apply") { editor.applyPreset(preset) }
                                Button(preset.isDefault ? "Stop Using for New Recordings" : "Use for New Recordings") {
                                    model.makeDefault(preset.isDefault ? nil : preset)
                                }
                                Divider()
                                Button("Delete Preset", role: .destructive) { model.deletePreset(preset) }
                            }
                        }
                    }
                    .fixedSize()
                    Button("Save…") { editor.showsSavePreset = true }
                        .help("Save this style as a preset (⇧⌘S)")
                }
            }
        }
    }
}

/// Save Style as Preset (S-029): a name, and whether new recordings use it.
struct SavePresetSheet: View {
    let editor: EditorModel
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isDefault = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("Launch video"))
                Toggle("Use for New Recordings", isOn: $isDefault)
            } header: {
                Text("Save Style as Preset")
            } footer: {
                Text("The background, padding, frame, shadow, and camera style. Each recording keeps its own crop.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: Layout.settingsWidth)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    model.savePreset(named: name, style: editor.style, isDefault: isDefault)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .fitsContent()
        .noInitialFocus()
    }
}
