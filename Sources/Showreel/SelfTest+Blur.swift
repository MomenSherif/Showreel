import AppKit
import ShowreelKit

/// Self-test checks for blurs (S-048, S-049).
extension SelfTest {
    static func blurs(_ editor: EditorModel) async {
        guard let undo = editor.undoManager, let duration = editor.sources?.duration, duration >= 1 else { return }
        let original = editor.blurs
        undo.removeAllActions()
        undo.groupsByEvent = false
        defer {
            undo.groupsByEvent = true
            editor.applyBlurs(original, named: "Blur")
            editor.selectBlur(nil)
            undo.removeAllActions()
        }
        func step(_ action: () -> Void) {
            undo.beginUndoGrouping()
            action()
            undo.endUndoGrouping()
        }
        step { editor.applyBlurs(BlurTrack(), named: "Blur") }

        // S-048: Add Blur puts a blur on the playhead, selected.
        editor.seek(to: 0)
        await editor.seeksSettled()
        step { editor.addBlur(atEditTime: 0) }
        let added = editor.selectedBlurRegion
        check("Add Blur puts a blur on the playhead and selects it",
              added?.start == 0 && abs((added?.end ?? 0) - min(BlurTrack.newLength, duration)) < 0.001,
              "\(String(describing: added))")
        check("a new blur is saved with the project", BlurTrack.decode(editor.project.blursData).regions.map(\.id) == [added?.id])
        check("a new blur is drawn", editor.renderStyle(for: editor.style).blurs.regions.count == 1)
        check("a selected blur leaves other selections", editor.selectedZoom == nil && editor.selectedCaption == nil
              && editor.selectedSegment == nil)
        editor.addBlur(atEditTime: 0.1)
        check("Add Blur on a blur selects it instead of adding one", editor.blurs.regions.count == 1)
        undo.undo()
        check("Undo removes the added blur", editor.blurs.regions.isEmpty && editor.selectedBlur == nil)

        // Blurs never overlap: a drag stops at the neighbor.
        let a = BlurRegion(start: 0, end: duration * 0.3), b = BlurRegion(start: duration * 0.6, end: duration)
        step { editor.applyBlurs(BlurTrack(regions: [a, b]), named: "Blur") }
        let moved = editor.blurs.moving(a.id, by: duration, duration: duration)
        check("a blur dragged into another stops at its edge",
              abs((moved.regions.first?.end ?? 0) - b.start) < 0.001, "\(moved.regions.map(\.end))")

        // S-049: drawing on the canvas is one undo step for the whole drag.
        editor.selectBlur(a.id)
        let before = editor.blurs
        step {
            for i in 1...8 {
                editor.previewBlurs(editor.blurs.changing(a.id) {
                    $0.rect = CropRect.spanning(CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.1 + Double(i) * 0.05, y: 0.5), minSide: 0.02)
                })
            }
            editor.commitBlurs(from: before, named: "Draw Blur")
        }
        check("drawing a blur sets its rectangle in recording coordinates",
              abs((editor.selectedBlurRegion?.rect.width ?? 0) - 0.4) < 0.001)
        undo.undo()
        check("one Undo reverts the whole drawing", editor.selectedBlurRegion?.rect == a.rect)

        step { editor.applyBlurs(editor.blurs.changing(a.id) { $0.style = .pixelate }, named: "Blur Style") }
        check("a blur's style is saved", BlurTrack.decode(editor.project.blursData).regions.first?.style == .pixelate)
        undo.undo()
        check("Undo puts the style back", editor.selectedBlurRegion?.style == .blur)

        step { editor.deleteSelectedBlur() }
        check("Delete Blur removes it and leaves the inspector", editor.blurs.regions.map(\.id) == [b.id] && editor.selectedBlur == nil)
        undo.undo()
        check("Undo brings the deleted blur back", editor.blurs.regions.count == 2)
    }
}
