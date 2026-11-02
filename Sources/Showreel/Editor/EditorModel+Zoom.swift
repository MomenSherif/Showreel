import AppKit
import AVFoundation
import ShowreelKit

/// Zoom edits (M5): the same undo, save, and redraw path as the style.
extension EditorModel {
    /// The selected zoom, shown in the inspector in place of the section (S-031).
    var selectedZoomSegment: ZoomSegment? {
        selectedZoom.flatMap { id in zooms.segments.first { $0.id == id } }
    }

    /// Selects a zoom, or with nil, goes back to the inspector's section.
    func selectZoom(_ id: ZoomSegment.ID?) {
        selectedZoom = id
    }

    /// Replaces the zooms as one undoable step called `name`, and saves them.
    func applyZooms(_ new: ZoomTrack, named name: String) {
        commitZooms(from: zooms, to: new, named: name)
    }

    /// Shows `new` on the canvas without an undo step or a save, while dragging.
    func previewZooms(_ new: ZoomTrack) {
        guard new != zooms else { return }
        zooms = new
        redraw()
    }

    /// Ends a drag that started at `old`: one undo step for the whole drag.
    func commitZooms(from old: ZoomTrack, named name: String) {
        commitZooms(from: old, to: zooms, named: name)
    }

    private func commitZooms(from old: ZoomTrack, to new: ZoomTrack, named name: String) {
        commitPart(from: old, to: new, named: name, current: { $0.zooms }) { editor, zooms in
            editor.zooms = zooms
            editor.project.zoomsData = zooms.encoded()
            if let id = editor.selectedZoom, !zooms.segments.contains(where: { $0.id == id }) { editor.selectedZoom = nil }
        }
    }

    /// The zooms with the segment `id` changed by `change`.
    func zooms(changing id: ZoomSegment.ID, _ change: (inout ZoomSegment) -> Void) -> ZoomTrack {
        var track = zooms
        if let i = track.segments.firstIndex(where: { $0.id == id }) { change(&track.segments[i]) }
        return track
    }

    /// The zoom camera through the zooms at the style's speed, following
    /// the recorded cursor. Kept until the zooms or the speed change.
    func zoomPath(for style: Style) -> ZoomPath {
        if let cache = zoomPathCache, cache.zooms == zooms, cache.speed == style.zoomSpeed { return cache.path }
        let path = ZoomPath(track: zooms, cursor: sources?.scene.cursor ?? CursorPath(),
                            duration: sources?.duration ?? edits.sourceDuration, speed: style.zoomSpeed)
        zoomPathCache = (zooms, style.zoomSpeed, path)
        return path
    }

    /// Add Zoom (Z) at the playhead, or a click on an empty spot of the zoom
    /// lane (S-032): a 2-second zoom on the cursor, selected. On a zoom it
    /// selects that zoom; with no room it beeps.
    func addZoom(atEditTime t: Double) {
        guard let sources, let source = edits.sourceTime(atEditTime: t) else { return }
        if let existing = zooms.segment(at: source) {
            selectZoom(existing.id)
            return
        }
        var track = zooms
        let spot = sources.scene.cursor.position(at: source) ?? CGPoint(x: 0.5, y: 0.5) // grid: ok normalized middle
        guard let zoom = track.add(at: source, duration: sources.duration, x: spot.x, y: spot.y) else {
            NSSound.beep()
            return
        }
        applyZooms(track, named: "Add Zoom")
        selectZoom(zoom.id)
    }

    /// Delete Zoom (⌫ or the inspector's button).
    func deleteSelectedZoom() {
        guard let id = selectedZoom else { return }
        var track = zooms
        track.segments.removeAll { $0.id == id }
        applyZooms(track, named: "Delete Zoom")
        selectedZoom = nil
    }

    /// The zoom's start in the edited video, or nil when the cut removed it.
    func editStart(of zoom: ZoomSegment) -> Double? {
        edits.editRanges(fromSource: zoom.start, to: zoom.end).first?.lowerBound
    }

    /// The recording's frame at a source time, uncropped: for Crop Screen
    /// and the zoom's focus preview.
    func sourceFrame(at time: Double, maxSize: CGSize = .zero) async -> CGImage? {
        guard let sources else { return nil }
        let generator = AVAssetImageGenerator(asset: sources.screen.asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        return try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }
}
