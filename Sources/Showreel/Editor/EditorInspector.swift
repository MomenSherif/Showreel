import SwiftUI
import ShowreelKit

/// The trailing inspector: a segmented picker of six sections, and one
/// grouped Form per section (docs/DESIGN.md, "Inspector").
struct EditorInspector: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: sectionBinding.animation(Motion.resolved(Motion.ui))) {
                ForEach(InspectorSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .help(section.title)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)

            if let zoom = editor.selectedZoomSegment {
                // A selected zoom takes the section's place (docs/DESIGN.md, "Inspector").
                HStack {
                    Label("Zoom", systemImage: TrackKind.zoom.symbol)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { withMotion(Motion.ui) { editor.selectZoom(nil) } }
                        .keyboardShortcut(.cancelAction)
                        .help("Back to \(editor.section.title) (Esc)")
                }
                .padding(.horizontal, Space.xl)
                ZoomInspector(editor: editor, zoom: zoom)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                Text(editor.section.title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xl)
                    .accessibilityAddTraits(.isHeader)

                SectionPage(section: editor.section, editor: editor)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// Picking a section also leaves a selected zoom.
    private var sectionBinding: Binding<InspectorSection> {
        Binding(get: { editor.section }, set: { section in
            editor.selectZoom(nil)
            editor.section = section
        })
    }
}

private struct SectionPage: View {
    let section: InspectorSection
    let editor: EditorModel

    private var project: Project { editor.project }

    var body: some View {
        switch section {
        case .background:
            BackgroundSection(editor: editor)
        case .screen:
            Form {
                Section("Size") {
                    StyleSlider(title: "Padding", editor: editor, value: \.padding, range: 0...0.3,
                                format: StyleSlider.percent, undoName: "Padding")
                    StyleSlider(title: "Rounding", editor: editor, value: \.rounding, range: 0...40,
                                format: StyleSlider.pixels, undoName: "Rounding")
                    LabeledContent {
                        Button("Crop Screen…", systemImage: "crop") { editor.showsCropSheet = true }
                            .help("Cut away the edges of the recording (⌥⌘C)")
                    } label: {
                        Text("Crop")
                        Text(cropText).foregroundStyle(.secondary)
                    }
                }
                Section("Frame") {
                    Picker("Frame", selection: frameBinding) {
                        Text("None").tag(Style.DeviceFrame.none)
                        Text("Border").tag(Style.DeviceFrame.border)
                        Text("Browser").tag(Style.DeviceFrame.browser)
                        Text("MacBook").tag(Style.DeviceFrame.macBook)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if editor.style.frame == .browser {
                        Toggle("Address Bar", isOn: urlBarBinding)
                        if editor.style.showsURLBar {
                            AddressField(editor: editor)
                        }
                    }
                }
                Section("Shadow") {
                    Picker("Effect", selection: effectBinding) {
                        Label("Shadow", systemImage: "shadow").tag(Style.Effect.shadow)
                        Label("Glow", systemImage: "sun.max").tag(Style.Effect.glow)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    StyleSlider(title: "Amount", editor: editor, value: \.effectAmount, range: 0...1,
                                format: StyleSlider.percent, undoName: editor.style.effect == .glow ? "Glow" : "Shadow")
                }
                .disabled(editor.style.background == .none)
                .help(editor.style.background == .none ? "Pick a background to show a shadow or glow" : "")
                Section("Recording") {
                    LabeledContent("Source", value: project.sourceName.isEmpty ? "Unknown" : project.sourceName)
                    LabeledContent("Size", value: "\(project.videoWidth) × \(project.videoHeight)")
                    LabeledContent("Length", value: TimeText.clock(editor.duration))
                }
            }
            .formStyle(.grouped)
        case .effects:
            EffectsSection(editor: editor)
        case .camera:
            if project.hasCamera {
                CameraSection(editor: editor)
            } else {
                Empty(title: "No Camera in This Recording", symbol: "person.crop.circle.badge.xmark",
                      line: "Turn on the camera for your next recording to show yourself in a bubble.")
            }
        case .captions:
            if project.hasMicrophone {
                CaptionsSection(editor: editor)
            } else {
                Empty(title: "No Voice Recorded", symbol: "mic.slash",
                      line: "Turn on the mic for your next recording to get captions.")
            }
        case .audio:
            if project.hasMicrophone || project.hasSystemAudio {
                Form {
                    Section("Tracks") {
                        LabeledContent("Microphone", value: project.hasMicrophone ? "Recorded" : "Off")
                        LabeledContent("System Audio", value: project.hasSystemAudio ? "Recorded" : "Off")
                    }
                }
                .formStyle(.grouped)
            } else {
                Empty(title: "No Audio in This Recording", symbol: "speaker.slash",
                      line: "Turn on the mic or system audio for your next recording.")
            }
        }
    }
}

extension SectionPage {
    var frameBinding: Binding<Style.DeviceFrame> {
        Binding(get: { editor.style.frame }, set: { frame in
            var style = editor.style
            style.frame = frame
            withMotion(Motion.ui) { editor.applyStyle(style, named: "Frame") }
        })
    }

    var urlBarBinding: Binding<Bool> {
        Binding(get: { editor.style.showsURLBar }, set: { shows in
            var style = editor.style
            style.showsURLBar = shows
            editor.applyStyle(style, named: shows ? "Show Address Bar" : "Hide Address Bar")
        })
    }

    var cropText: String {
        let crop = editor.style.crop
        guard !crop.isFull, let size = editor.sources?.naturalSize else { return "None" }
        let pixels = crop.pixels(of: size)
        return "\(Int(pixels.width)) × \(Int(pixels.height))"
    }

    var effectBinding: Binding<Style.Effect> {
        Binding(get: { editor.style.effect }, set: { effect in
            var style = editor.style
            style.effect = effect
            editor.applyStyle(style, named: effect == .glow ? "Glow" : "Shadow")
        })
    }
}

/// The Browser frame's address. Typing is not an undo step per key: the
/// address is applied on Return or when the field loses focus.
private struct AddressField: View {
    let editor: EditorModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Address", text: $text, prompt: Text("example.com"))
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onAppear { text = editor.style.url }
            .onChange(of: editor.style.url) { _, url in if !focused { text = url } }
    }

    private func commit() {
        let url = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url != editor.style.url else { return }
        var style = editor.style
        style.url = url
        editor.applyStyle(style, named: "Address")
    }
}

private struct Empty: View {
    let title: String
    let symbol: String
    let line: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(line))
            .padding(.top, Space.section)
    }
}
