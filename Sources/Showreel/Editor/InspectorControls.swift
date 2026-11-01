import SwiftUI
import ShowreelKit

/// A labeled slider for one style value, with the value shown beside the
/// title. The canvas follows the drag live; the whole drag is one undo step
/// called `undoName` (S-020, S-023).
struct StyleSlider: View {
    let title: String
    let editor: EditorModel
    let value: WritableKeyPath<Style, Double>
    let range: ClosedRange<Double>
    let format: (Double) -> String
    let undoName: String
    @State private var dragStart: Style?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(title)
                Spacer()
                Text(format(editor.style[keyPath: value]))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: binding, in: range) { editing in
                if editing {
                    dragStart = editor.style
                } else if let start = dragStart {
                    editor.commitStyle(from: start, named: undoName)
                    dragStart = nil
                }
            }
            .labelsHidden()
            .accessibilityLabel(title)
            .accessibilityValue(format(editor.style[keyPath: value]))
        }
    }

    private var binding: Binding<Double> {
        Binding(get: { editor.style[keyPath: value] }, set: { new in
            var style = editor.style
            style[keyPath: value] = new
            // Arrow keys and VoiceOver change the value without a drag: apply
            // each such change as its own step.
            if dragStart == nil {
                editor.applyStyle(style, named: undoName)
            } else {
                editor.previewStyle(style)
            }
        })
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    static func pixels(_ value: Double) -> String { "\(Int(value.rounded())) px" }
}
