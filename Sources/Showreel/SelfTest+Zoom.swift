import AppKit
import ShowreelKit

/// Self-test checks for zooms (M5).
extension SelfTest {
    /// S-031: a zoom is selected and edited in the inspector; each change is
    /// saved and is one undo step.
    static func zooms(_ editor: EditorModel) async {
        guard let undo = editor.undoManager, editor.duration >= 1.5 else { return }
        let original = editor.zooms
        undo.removeAllActions()
        undo.groupsByEvent = false
        defer {
            undo.groupsByEvent = true
            editor.applyZooms(original, named: "Zoom")
            undo.removeAllActions()
        }
        func step(_ action: () -> Void) {
            undo.beginUndoGrouping()
            action()
            undo.endUndoGrouping()
        }
        let zoom = ZoomSegment(start: 0, end: min(editor.duration, 1.5), x: 0.3, y: 0.3)
        step { editor.applyZooms(ZoomTrack(segments: [zoom]), named: "Zoom") }
        editor.selectZoom(zoom.id)
        check("a selected zoom shows in the inspector", editor.selectedZoomSegment?.id == zoom.id && editor.selectedSegment == nil)

        step { editor.applyZooms(editor.zooms(changing: zoom.id) { $0.scale = 3.5 }, named: "Zoom Scale") }
        check("a zoom's scale is saved", ZoomTrack.decode(editor.project.zoomsData)?.segments.first?.scale == 3.5)
        check("the zoom is drawn at its scale", editor.renderStyle(for: editor.style).zooms.view(at: 0.75).scale == 3.5)
        undo.undo()
        check("Undo puts the scale back", editor.selectedZoomSegment?.scale == 2, "\(editor.selectedZoomSegment?.scale ?? 0)")

        // A drag on the focus preview: many points, one undo step, focus becomes Fixed Point.
        let start = editor.zooms
        step {
            for i in 1...10 {
                editor.previewZooms(editor.zooms(changing: zoom.id) { $0.x = 0.3 + Double(i) * 0.05; $0.focus = .fixed })
            }
            editor.commitZooms(from: start, named: "Zoom Focus")
        }
        let moved = editor.selectedZoomSegment
        check("dragging the focus point fixes it where the drag ended", moved?.focus == .fixed && moved?.x == 0.8)
        undo.undo()
        check("one Undo reverts the whole focus drag",
              editor.selectedZoomSegment?.x == 0.3 && editor.selectedZoomSegment?.focus == .auto)

        step { editor.deleteSelectedZoom() }
        check("Delete Zoom removes it and leaves the inspector", editor.zooms.segments.isEmpty && editor.selectedZoom == nil)
        undo.undo()
        check("Undo brings the deleted zoom back", editor.zooms.segments.map(\.id) == [zoom.id])
    }
}
