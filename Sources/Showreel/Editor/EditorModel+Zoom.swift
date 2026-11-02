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
        if id != nil { selectedSegment = nil }
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
        commitDrawn(from: old, to: new, named: name, current: { $0.zooms }) { editor, zooms in
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
