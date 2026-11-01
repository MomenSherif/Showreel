import SwiftUI
import ShowreelKit

/// Inspector > Camera (S-028): show or hide the camera, its size, shape,
/// border, and shadow, and the position dragged on the canvas.
struct CameraSection: View {
    let editor: EditorModel

    var body: some View {
        Form {
            Section {
                Toggle("Show Camera", isOn: binding(\.cameraVisible, named: "Show Camera"))
            }
            Section("Bubble") {
                StyleSlider(title: "Size", editor: editor, value: \.cameraScale, range: 0.5...2,
                            format: StyleSlider.percent, undoName: "Camera Size")
                Picker("Shape", selection: shapeBinding) {
                    Text("As Recorded").tag(Style.CameraShape?.none)
                    Text("Circle").tag(Style.CameraShape?.some(.circle))
                    Text("Rounded Square").tag(Style.CameraShape?.some(.roundedSquare))
                }
                StyleSlider(title: "Border", editor: editor, value: \.cameraBorder, range: 0...1,
                            format: StyleSlider.percent, undoName: "Camera Border")
                StyleSlider(title: "Shadow", editor: editor, value: \.cameraShadow, range: 0...1,
                            format: StyleSlider.percent, undoName: "Camera Shadow")
            }
            .disabled(!editor.style.cameraVisible)
            Section {
                LabeledContent("Position", value: editor.style.cameraPosition == nil ? "As Recorded" : "Moved")
                Button("Reset Position") {
                    var style = editor.style
                    style.cameraPosition = nil
                    editor.applyStyle(style, named: "Reset Camera Position")
                }
                .disabled(editor.style.cameraPosition == nil)
            } footer: {
                Text("Drag the camera on the canvas to move it for the whole video.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!editor.style.cameraVisible)
        }
        .formStyle(.grouped)
    }

    private func binding(_ key: WritableKeyPath<Style, Bool>, named name: String) -> Binding<Bool> {
        Binding(get: { editor.style[keyPath: key] }, set: { value in
            var style = editor.style
            style[keyPath: key] = value
            editor.applyStyle(style, named: name)
        })
    }

    private var shapeBinding: Binding<Style.CameraShape?> {
        Binding(get: { editor.style.cameraShape }, set: { shape in
            var style = editor.style
            style.cameraShape = shape
            editor.applyStyle(style, named: "Camera Shape")
        })
    }
}
