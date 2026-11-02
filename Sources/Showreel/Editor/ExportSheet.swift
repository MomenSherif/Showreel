import SwiftUI
import ShowreelKit

/// File > Export… (S-036): the format, size, frame rate, and quality, with
/// the file size they make. Export… then asks where to save.
struct ExportSheet: View {
    let editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings: ExportSettings

    init(editor: EditorModel) {
        self.editor = editor
        _settings = State(initialValue: editor.savedExportSettings)
    }

    var body: some View {
        Form {
            Section {
                ExportChoices(settings: $settings, canvas: canvas)
            } header: {
                Text("Export “\(editor.project.title)”")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(editor.project.title)
            }
            Section {
                LabeledContent("Estimated Size", value: estimate)
                    .accessibilityValue(estimate)
            }
        }
        .formStyle(.grouped)
        .frame(width: Layout.settingsWidth)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Export…") {
                    // The sheet is the key window; the save panel goes on its editor.
                    let settings = settings, window = NSApp.keyWindow.map { $0.sheetParent ?? $0 }
                    dismiss()
                    // AppKit holds the save panel until this sheet is gone: one modal at a time.
                    Task { @MainActor in editor.chooseExportFile(settings: settings, window: window) }
                }
                .disabled(canvas == .zero)
            }
        }
        .fitsContent()
        .noInitialFocus()
    }

    private var canvas: CGSize { editor.canvasSize }

    /// "1920 × 1080 · about 48 MB".
    private var estimate: String {
        let size = settings.outputSize(canvas: canvas)
        let bytes = settings.estimatedBytes(canvas: canvas, duration: editor.duration,
                                            hasAudio: editor.hasAudio && settings.format.hasAudio)
        let file = bytes.formatted(.byteCount(style: .file))
        return "\(Int(size.width)) × \(Int(size.height)) · about \(file)"
    }
}

/// Format, Resolution, Frame Rate, and Quality: in the Export sheet and in
/// Settings > Export (S-045). With a `canvas`, it says when the export is
/// larger than the recording.
struct ExportChoices: View {
    @Binding var settings: ExportSettings
    var canvas: CGSize?

    var body: some View {
        Picker(selection: format) {
            ForEach(ExportSettings.Format.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
            Text("Format")
            Text(settings.format.caption)
        }
        .pickerStyle(.segmented)
        Picker(selection: $settings.resolution) {
            ForEach(settings.resolutions, id: \.self) { Text($0.title).tag($0) }
        } label: {
            Text("Resolution")
            if let canvas, settings.isUpscaled(canvas: canvas) {
                Text("Larger than the recording, so it will look softer.")
            }
        }
        Picker("Frame Rate", selection: $settings.fps) {
            ForEach(settings.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
        }
        .pickerStyle(.segmented)
        if settings.format != .gif {
            Picker("Quality", selection: $settings.quality) {
                ForEach(ExportSettings.Quality.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var format: Binding<ExportSettings.Format> {
        Binding(get: { settings.format }, set: { settings = settings.with(format: $0) })
    }
}
