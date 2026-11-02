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
        let drawn = editor.renderStyle(for: editor.style).zoomPath.view(at: 0.75).scale
        check("the zoom is drawn at its scale", abs(drawn - 3.5) < 0.001, "\(drawn)")
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
        await zoomEditing(editor, step: step)
    }

    /// S-032: zooms are added, moved, and resized, and never overlap.
    static func zoomEditing(_ editor: EditorModel, step: (() -> Void) -> Void) async {
        guard let undo = editor.undoManager, let duration = editor.sources?.duration, duration >= 1.8 else { return }
        let a = ZoomSegment(start: 0, end: 0.6), b = ZoomSegment(start: 1.2, end: 1.8)
        step { editor.applyZooms(ZoomTrack(segments: [a, b]), named: "Zoom") }
        func drag(_ name: String, _ change: (ZoomTrack) -> ZoomTrack) {
            let start = editor.zooms, target = change(start)
            step {
                editor.previewZooms(target)
                editor.commitZooms(from: start, named: name)
            }
        }
        func overlaps() -> Bool { zip(editor.zooms.segments, editor.zooms.segments.dropFirst()).contains { $0.end > $1.start + 1e-9 } }

        drag("Move Zoom") { $0.moving(a.id, by: 5, duration: duration) }
        let moved = editor.zooms.segments.first { $0.id == a.id }
        check("dragging a zoom into the next one stops at its edge", moved?.end == b.start && !overlaps(),
              "\(moved.map { "\($0.start)…\($0.end)" } ?? "none")")
        undo.undo()
        drag("Resize Zoom") { $0.resizing(b.id, edge: .start, by: -5, duration: duration) }
        check("dragging a zoom's edge stops at the zoom before it",
              editor.zooms.segments.last?.start == a.end && !overlaps())
        undo.undo()
        check("Undo puts the resized zoom back", editor.zooms.segments.last?.start == b.start)

        editor.seek(to: 0.3)
        await editor.seeksSettled()
        editor.addZoom(atEditTime: editor.playhead.time)
        check("Add Zoom on a zoom selects it", editor.zooms.segments.count == 2 && editor.selectedZoom == a.id)
        step { editor.applyZooms(ZoomTrack(), named: "Zoom") }
        step { editor.addZoom(atEditTime: 0.2) }
        let added = editor.zooms.segments.first, source = editor.edits.sourceTime(atEditTime: 0.2) ?? -1
        // Near the end of a short recording, the 2-second zoom starts earlier so it fits.
        check("Add Zoom puts a selected zoom over the playhead", editor.zooms.segments.count == 1
              && added.map { $0.start <= source && source <= $0.end } == true && editor.selectedZoom == added?.id,
              "\(editor.zooms.segments.map { "\($0.start)…\($0.end)" }) at \(source)")
        let clip = NSApp.mainMenu?.item(withTitle: "Clip")?.submenu?.items.map(\.title) ?? []
        check("the Clip menu has Add Zoom", clip.contains("Add Zoom"), clip.joined(separator: ", "))

        // S-033: Zoom Motion is part of the style, saved, and changes how fast the camera moves.
        let zoom = ZoomSegment(start: 0.2, end: 1.8)
        step { editor.applyZooms(ZoomTrack(segments: [zoom]), named: "Zoom") }
        func scaleSoon() -> Double { editor.renderStyle(for: editor.style).zoomPath.view(at: 0.4).scale }
        var slow = editor.style
        slow.zoomSpeed = .slow
        step { editor.applyStyle(slow, named: "Zoom Motion") }
        let slowScale = scaleSoon()
        var fast = editor.style
        fast.zoomSpeed = .fast
        step { editor.applyStyle(fast, named: "Zoom Motion") }
        check("Zoom Motion is saved with the project", Style.decode(editor.project.styleData).zoomSpeed == .fast)
        check("Fast zooms in sooner than Slow", scaleSoon() > slowScale, "\(scaleSoon()) vs \(slowScale)")
        undo.undo()
        undo.undo()
    }
}
