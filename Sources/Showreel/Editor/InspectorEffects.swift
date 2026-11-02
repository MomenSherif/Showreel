import SwiftUI
import ShowreelKit

/// Effects (M5): how zooms move. The cursor and click effects join it in
/// S-034 and S-035.
struct EffectsSection: View {
    let editor: EditorModel

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
        }
        .formStyle(.grouped)
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
