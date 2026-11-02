import SwiftUI
import ShowreelEngine
import ShowreelKit

/// The Captions section (S-039): Generate Captions, its progress, and what it made.
struct CaptionsSection: View {
    let editor: EditorModel

    var body: some View {
        if let job = editor.captionJob {
            JobView(editor: editor, job: job)
        } else if editor.captions.captions.isEmpty {
            VStack(spacing: 0) {
                ContentUnavailableView {
                    Label("No Captions", systemImage: InspectorSection.captions.symbol)
                } description: {
                    Text("Make timed captions from your voice. It runs on this Mac.")
                } actions: {
                    GenerateButton(editor: editor, title: "Generate Captions")
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, Space.section)
                .fixedSize(horizontal: false, vertical: true)
                Form { SpeechChoices() }
                    .formStyle(.grouped)
            }
        } else {
            Form {
                Section {
                    LabeledContent("Lines", value: "\(editor.captions.captions.count)")
                    LabeledContent("Language", value: EditorModel.languageName(editor.captions.language))
                }
                SpeechChoices()
                Section {
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

/// How captions look in the video (S-041, S-056, S-057): a caption style
/// to start from, where and how big, and every part of the look to make it
/// your own. Each change is one undo step, and presets carry it with the
/// rest of the style.
private struct CaptionStyleSection: View {
    let editor: EditorModel
    @Bindable private var looks = CaptionLooks.shared
    /// A color change in progress: the well sends many values; one undo step
    /// is made when they stop.
    @State private var colorStart: Style?
    @State private var colorCommit: Task<Void, Never>?
    @State private var saving = false
    @State private var renaming: CaptionLook?
    @State private var name = ""

    private var look: CaptionStyle { editor.style.captions }

    var body: some View {
        Section {
            Toggle("Show in Video", isOn: binding(\.isVisible, named: "Show Captions"))
            Group {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.captionTile.width), spacing: Space.sm)], spacing: Space.sm) {
                    ForEach(CaptionLook.all) { tile($0) }
                    ForEach(looks.saved.looks) { saved in
                        tile(saved)
                            .contextMenu {
                                Button("Rename…") {
                                    name = saved.name
                                    renaming = saved
                                }
                                Button("Delete Style", role: .destructive) { looks.delete(saved.id) }
                            }
                    }
                }
                .padding(.vertical, Space.xs)
                LabeledContent {
                    Button("Save Style…") { askToSave() }
                        .help("Keep this look to use in any project (⌥⇧⌘S)")
                } label: {
                    Text(looks.match(look)?.name ?? "Custom")
                    Text(looks.match(look) == nil ? "Your own look." : "Change anything below to make it your own.")
                        .foregroundStyle(.secondary)
                }
                Picker("Position", selection: binding(\.position, named: "Caption Position")) {
                    Text("Bottom").tag(CaptionStyle.Position.bottom)
                    Text("Middle").tag(CaptionStyle.Position.middle)
                    Text("Top").tag(CaptionStyle.Position.top)
                }
                .pickerStyle(.segmented)
                StyleSlider(title: "Size", editor: editor, value: \.captions.size, range: CaptionStyle.sizeRange,
                            format: StyleSlider.percent, undoName: "Caption Size")
            }
            .disabled(!look.isVisible)
        } header: {
            Text("Style")
        }
        Group {
            Section("Text") {
                Picker("Font", selection: binding(\.font, named: "Caption Font")) {
                    Text("System").tag(CaptionStyle.Font.system)
                    Text("Rounded").tag(CaptionStyle.Font.rounded)
                    Text("Serif").tag(CaptionStyle.Font.serif)
                    Text("Monospaced").tag(CaptionStyle.Font.mono)
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag(CaptionStyle.Font.family($0)) }
                }
                Picker("Weight", selection: binding(\.weight, named: "Caption Weight")) {
                    ForEach(CaptionStyle.Weight.allCases, id: \.self) { Text(Self.title($0)).tag($0) }
                }
                ColorPicker("Color", selection: colorBinding(\.textColor, named: "Caption Text Color"), supportsOpacity: false)
                Toggle("All Caps", isOn: binding(\.allCaps, named: "All Caps"))
            }
            Section("Box") {
                Toggle("Show Box", isOn: binding(\.showsBox, named: "Caption Box"))
                    .help("A rounded box behind the caption text")
                Group {
                    ColorPicker("Color", selection: colorBinding(\.boxColor, named: "Caption Box Color"), supportsOpacity: false)
                    StyleSlider(title: "Opacity", editor: editor, value: \.captions.boxOpacity, range: 0.1...1,
                                format: StyleSlider.percent, undoName: "Caption Box Opacity")
                }
                .disabled(!look.showsBox)
            }
            Section("Outline and Shadow") {
                StyleSlider(title: "Outline", editor: editor, value: \.captions.outline, range: 0...1,
                            format: { $0 < 0.005 ? "None" : StyleSlider.percent($0) }, undoName: "Caption Outline")
                ColorPicker("Outline Color", selection: colorBinding(\.outlineColor, named: "Caption Outline Color"),
                            supportsOpacity: false)
                    .disabled(look.outline < 0.005)
                Picker("Shadow", selection: binding(\.shadow, named: "Caption Shadow")) {
                    Text("None").tag(CaptionStyle.Shadow.none)
                    Text("Soft").tag(CaptionStyle.Shadow.soft)
                    Text("Glow").tag(CaptionStyle.Shadow.glow)
                }
                .pickerStyle(.segmented)
                .help("Soft: a drop shadow. Glow: light in the text color.")
            }
            Section {
                Picker("Highlight", selection: binding(\.highlight, named: "Highlight Spoken Word")) {
                    Text("None").tag(CaptionStyle.Highlight.none)
                    Text("Pill").tag(CaptionStyle.Highlight.pill)
                    Text("Word Color").tag(CaptionStyle.Highlight.word)
                    Text("Karaoke").tag(CaptionStyle.Highlight.karaoke)
                }
                ColorPicker("Highlight Color", selection: colorBinding(\.highlightColor, named: "Highlight Color"), supportsOpacity: false)
                    .disabled(!look.highlightsWord)
            } header: {
                Text("Spoken Word")
            } footer: {
                Text(highlightFooter).foregroundStyle(.secondary)
            }
        }
        .disabled(!look.isVisible)
        .alert("Save Caption Style", isPresented: $saving) {
            TextField("Name", text: $name)
            Button("Save") { looks.save(look, named: name) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keep this look to use in any project. Size and position are not part of it.")
        }
        .alert("Rename Caption Style", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Rename") { if let renaming { looks.rename(renaming.id, to: name) } }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { if editor.savesCaptionStyle { askToSave() } }
        .onChange(of: editor.savesCaptionStyle) { _, asked in if asked { askToSave() } }
    }

    /// One caption style, drawn by the video's own caption code.
    private func tile(_ named: CaptionLook) -> some View {
        Tile(name: named.name, isSelected: look.hasLook(of: named.style),
             size: Layout.captionTile) {
            CaptionSample(style: named.style)
        } action: {
            var style = editor.style
            style.captions = look.withLook(of: named.style)
            withMotion(Motion.select) { editor.applyStyle(style, named: "\(named.name) Captions") }
        }
    }

    private func askToSave() {
        editor.savesCaptionStyle = false
        name = ""
        saving = true
    }

    /// Every font on this Mac, plus the chosen one when it is not here.
    private var families: [String] {
        if case .family(let chosen) = look.font, !CaptionLooks.fontFamilies.contains(chosen) {
            return [chosen] + CaptionLooks.fontFamilies
        }
        return CaptionLooks.fontFamilies
    }

    private var highlightFooter: String {
        switch look.highlight {
        case .none: "Every word looks the same."
        case .pill: "A colored pill behind the word being spoken."
        case .word: "The word being spoken turns the highlight color."
        case .karaoke: "Words turn the highlight color as they are spoken."
        }
    }

    static func title(_ weight: CaptionStyle.Weight) -> String {
        switch weight {
        case .regular: "Regular"
        case .medium: "Medium"
        case .semibold: "Semibold"
        case .bold: "Bold"
        case .heavy: "Heavy"
        case .black: "Black"
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
    private func colorBinding(_ path: WritableKeyPath<CaptionStyle, RGB>, named name: String) -> Binding<Color> {
        Binding(get: { Color(editor.style.captions[keyPath: path]) }, set: { color in
            let start = colorStart ?? editor.style
            colorStart = start
            var style = editor.style
            style.captions[keyPath: path] = RGB(color)
            editor.previewStyle(style)
            colorCommit?.cancel()
            colorCommit = Task {
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled else { return }
                editor.commitStyle(from: start, named: name)
                colorStart = nil
            }
        })
    }
}

/// "Say hello" in a caption style, small, drawn once per style.
private struct CaptionSample: View {
    let style: CaptionStyle
    @Environment(\.displayScale) private var scale

    var body: some View {
        if let image = Self.image(style, scale: scale) {
            Image(decorative: image, scale: scale)
                .resizable()
        }
    }

    @MainActor private static var cache: [CaptionStyle: CGImage] = [:]

    @MainActor static func image(_ style: CaptionStyle, scale: CGFloat) -> CGImage? {
        if let cached = cache[style] { return cached }
        let size = CGSize(width: Layout.captionTile.width * scale, height: Layout.captionTile.height * scale)
        let image = CaptionPainter.sample(style, size: size, scale: 9)
        if cache.count > 64 { cache.removeAll() }
        cache[style] = image
        return image
    }
}

/// Speech Model and Language for the next Generate Captions (S-050), the
/// same choices as Settings > Captions. A model that is not on this Mac
/// says so, with its Download button.
private struct SpeechChoices: View {
    @Bindable private var models = SpeechModels.shared

    var body: some View {
        Section {
            Picker("Speech Model", selection: $models.model) {
                ForEach(SpeechModel.allCases) { Text($0.title).tag($0) }
            }
            LanguagePicker()
            if !models.availability(of: models.model).isReady {
                LabeledContent {
                    ModelAction(model: models.model, compact: true)
                } label: {
                    Text("Download \(models.model.title) in Settings > Captions, or here.")
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                    // Arabic is typed and shown from the right (S-054).
                    .multilineTextAlignment(TextDirection.isRightToLeft(text, language: editor.captions.language)
                                            ? .trailing : .leading)
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
