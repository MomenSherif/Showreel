import SwiftUI
import ShowreelKit

/// The Captions section (S-039): Generate Captions, its progress, and what it made.
struct CaptionsSection: View {
    let editor: EditorModel

    var body: some View {
        if let job = editor.captionJob {
            JobView(editor: editor, job: job)
        } else if editor.captions.captions.isEmpty {
            ContentUnavailableView {
                Label("No Captions", systemImage: InspectorSection.captions.symbol)
            } description: {
                Text("Make timed captions from your voice. It runs on this Mac.")
            } actions: {
                GenerateButton(editor: editor, title: "Generate Captions")
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, Space.section)
        } else {
            Form {
                Section {
                    LabeledContent("Lines", value: "\(editor.captions.captions.count)")
                    LabeledContent("Language", value: EditorModel.languageName(editor.captions.language))
                    LabeledContent {
                        GenerateButton(editor: editor, title: "Generate Again")
                    } label: {
                        Text("Made from your voice")
                        Text("Generating again replaces these captions.").foregroundStyle(.secondary)
                    }
                }
                CaptionStyleSection(editor: editor)
            }
            .formStyle(.grouped)
        }
    }
}

/// How captions look in the video (S-041). Each change is one undo step,
/// and presets carry it with the rest of the style.
private struct CaptionStyleSection: View {
    let editor: EditorModel
    @State private var colorStart: Style?
    @State private var colorCommit: Task<Void, Never>?

    private var look: CaptionStyle { editor.style.captions }

    var body: some View {
        Section("Style") {
            Toggle("Show in Video", isOn: binding(\.isVisible, named: "Show Captions"))
            Group {
                StyleSlider(title: "Size", editor: editor, value: \.captions.size, range: CaptionStyle.sizeRange,
                            format: StyleSlider.percent, undoName: "Caption Size")
                Picker("Position", selection: binding(\.position, named: "Caption Position")) {
                    Text("Bottom").tag(CaptionStyle.Position.bottom)
                    Text("Top").tag(CaptionStyle.Position.top)
                }
                .pickerStyle(.segmented)
                Picker("Box", selection: binding(\.box, named: "Caption Box")) {
                    Text("None").tag(CaptionStyle.Box.none)
                    Text("Dark").tag(CaptionStyle.Box.dark)
                    Text("Light").tag(CaptionStyle.Box.light)
                }
                .help("The box behind the caption text")
                Toggle("Highlight Spoken Word", isOn: binding(\.highlightsWord, named: "Highlight Spoken Word"))
                ColorPicker("Highlight Color", selection: colorBinding, supportsOpacity: false)
                    .disabled(!look.highlightsWord)
            }
            .disabled(!look.isVisible)
        }
    }

    /// A caption style value; each change is one undo step called `name`.
    private func binding<Value>(_ path: WritableKeyPath<CaptionStyle, Value>, named name: String) -> Binding<Value> {
        Binding(get: { editor.style.captions[keyPath: path] }, set: { value in
            var style = editor.style
            style.captions[keyPath: path] = value
            withMotion(Motion.ui) { editor.applyStyle(style, named: name) }
        })
    }

    /// The color well sends many changes while it is open: the canvas
    /// follows each, and they settle into one undo step.
    private var colorBinding: Binding<Color> {
        Binding(get: { Color(look.highlightColor) }, set: { color in
            let start = colorStart ?? editor.style
            colorStart = start
            var style = editor.style
            style.captions.highlightColor = RGB(color)
            editor.previewStyle(style)
            colorCommit?.cancel()
            colorCommit = Task {
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled else { return }
                editor.commitStyle(from: start, named: "Highlight Color")
                colorStart = nil
            }
        })
    }
}

private struct GenerateButton: View {
    let editor: EditorModel
    let title: String

    var body: some View {
        Button(title, systemImage: "captions.bubble") { editor.generateCaptions() }
            .disabled(!editor.canGenerateCaptions)
            .help("Make captions from the microphone recording, on this Mac")
    }
}

/// Progress with Cancel while it runs; the reason and Try Again when it failed.
private struct JobView: View {
    let editor: EditorModel
    let job: CaptionJob

    var body: some View {
        Form {
            Section {
                if let progress = job.progress {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(progress.text)
                        HStack(spacing: Space.md) {
                            ProgressView(value: progress.fraction)
                                .accessibilityLabel(progress.text)
                            Button("Cancel") { job.cancel() }
                                .controlSize(.small)
                                .help("Stop making captions")
                        }
                    }
                } else if let failure = job.failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Try Again") { editor.generateCaptions() }
                            .help("Make captions from the microphone recording again")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The selected caption in the inspector (S-040): its text, timing, and
/// Delete. Return or leaving the field applies the text as one undo step.
struct CaptionInspector: View {
    let editor: EditorModel
    let caption: Caption
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Caption text", text: $text, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...4)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            } footer: {
                Text("Return applies the text.").foregroundStyle(.secondary)
            }
            Section("Timing") {
                LabeledContent("Starts", value: editor.editStart(of: caption).map(TimeText.precise) ?? "Cut")
                LabeledContent("Length", value: ClipBlock.length(caption.length))
            }
            Section {
                Button("Delete Caption", role: .destructive) { editor.deleteSelectedCaption() }
                    .help("Remove this caption (⌫)")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            text = caption.text
            if editor.editsCaptionText {
                editor.editsCaptionText = false
                focused = true
            }
        }
        // Done, Esc, or another selection also applies what was typed.
        .onDisappear(perform: commit)
        .onChange(of: caption.text) { _, new in if !focused { text = new } }
        .onChange(of: editor.editsCaptionText) { _, edit in
            if edit {
                editor.editsCaptionText = false
                focused = true
            }
        }
    }

    /// Empty text goes back to the caption's text.
    private func commit() {
        editor.setText(text, ofCaption: caption.id)
        if caption.withText(text) == nil { text = caption.text }
    }
}
