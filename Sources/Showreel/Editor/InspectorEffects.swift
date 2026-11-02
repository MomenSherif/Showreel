import SwiftUI
import ShowreelKit

/// Effects (M5): how zooms move, how the cursor is drawn, and the marks at
/// clicks.
struct EffectsSection: View {
    let editor: EditorModel
    /// A color change in progress: the well sends many values; one undo step
    /// is made when they stop.
    @State private var changeStart: Style?
    @State private var colorCommit: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Picker("Motion", selection: speedBinding) {
                    ForEach(ZoomSpeed.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Zooms", value: zoomCount)
            } header: {
                Text("Zoom")
            } footer: {
                Text("How fast zooms move in, out, and from one spot to the next.")
                    .foregroundStyle(.secondary)
            }
            Section {
                StyleSlider(title: "Size", editor: editor, value: \.cursorScale, range: 1...3,
                            format: Self.times, undoName: "Cursor Size")
                StyleSlider(title: "Smoothing", editor: editor, value: \.cursorSmoothing, range: 0...1,
                            format: Self.smoothing, undoName: "Cursor Smoothing")
                Toggle("Hide When Idle", isOn: hidesBinding)
                    .help("Fade the cursor out after it has been still for 2 seconds")
            } header: {
                Text("Cursor")
            } footer: {
                Text("The cursor is drawn from the recording, so it stays sharp at any size.")
                    .foregroundStyle(.secondary)
            }
            .disabled(editor.sources?.events == nil)
            Section {
                Picker("Effect", selection: clickBinding) {
                    Text("None").tag(Style.ClickEffect.none)
                    Text("Ripple").tag(Style.ClickEffect.ripple)
                    Text("Ring").tag(Style.ClickEffect.ring)
                }
                .pickerStyle(.segmented)
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                    .disabled(editor.style.clickEffect == .none)
            } header: {
                Text("Clicks")
            } footer: {
                Text("A mark at each click, for 0.4 seconds.")
                    .foregroundStyle(.secondary)
            }
            .disabled(editor.sources?.events == nil)
        }
        .formStyle(.grouped)
    }

    static func times(_ value: Double) -> String { String(format: "%.1f×", value) }

    static func smoothing(_ value: Double) -> String {
        switch value {
        case ..<0.01: "Off"
        case ..<0.34: "Low"
        case ..<0.67: "Medium"
        default: "High"
        }
    }

    private var clickBinding: Binding<Style.ClickEffect> {
        Binding(get: { editor.style.clickEffect }, set: { effect in
            var style = editor.style
            style.clickEffect = effect
            editor.applyStyle(style, named: "Click Effect")
        })
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(editor.style.clickColor) }, set: { color in
            let start = changeStart ?? editor.style
            changeStart = start
            var style = editor.style
            style.clickColor = RGB(color)
            editor.previewStyle(style)
            colorCommit?.cancel()
            colorCommit = Task {
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled else { return }
                editor.commitStyle(from: start, named: "Click Color")
                changeStart = nil
            }
        })
    }

    private var hidesBinding: Binding<Bool> {
        Binding(get: { editor.style.cursorHidesWhenIdle }, set: { hides in
            var style = editor.style
            style.cursorHidesWhenIdle = hides
            editor.applyStyle(style, named: hides ? "Hide Idle Cursor" : "Show Idle Cursor")
        })
    }

    private var zoomCount: String {
        let n = editor.zooms.segments.count
        return n == 0 ? "None" : "\(n)"
    }

    private var speedBinding: Binding<ZoomSpeed> {
        Binding(get: { editor.style.zoomSpeed }, set: { speed in
            var style = editor.style
            style.zoomSpeed = speed
            editor.applyStyle(style, named: "Zoom Motion")
        })
    }
}
