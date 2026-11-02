import AppKit
import CoreGraphics
import ShowreelKit

/// Blur edits (S-048, S-049): the same undo, save, and redraw path as zooms.
extension EditorModel {
    /// The selected blur, shown in the inspector and with handles on the canvas.
    var selectedBlurRegion: BlurRegion? {
        selectedBlur.flatMap { id in blurs.regions.first { $0.id == id } }
    }

    /// Selects a blur, or with nil, goes back to the inspector's section.
    func selectBlur(_ id: BlurRegion.ID?) {
        selectedBlur = id
        if id != nil {
            selectedSegment = nil
            selectedZoom = nil
            selectedCaption = nil
        }
    }

    /// Replaces the blurs as one undoable step called `name`, and saves them.
    func applyBlurs(_ new: BlurTrack, named name: String) {
        commitBlurs(from: blurs, to: new, named: name)
    }

    /// Shows `new` on the canvas without an undo step or a save, while dragging.
    func previewBlurs(_ new: BlurTrack) {
        guard new != blurs else { return }
        blurs = new
        redraw()
    }

    /// Ends a drag that started at `old`: one undo step for the whole drag.
    func commitBlurs(from old: BlurTrack, named name: String) {
        commitBlurs(from: old, to: blurs, named: name)
    }

    private func commitBlurs(from old: BlurTrack, to new: BlurTrack, named name: String) {
        commitPart(from: old, to: new, named: name, current: { $0.blurs }) { editor, blurs in
            editor.blurs = blurs
            editor.project.blursData = blurs.regions.isEmpty ? nil : blurs.encoded()
            if let id = editor.selectedBlur, !blurs.regions.contains(where: { $0.id == id }) { editor.selectedBlur = nil }
        }
    }

    /// Add Blur (B) at the playhead, or a click on an empty spot of the blur
    /// lane: a 3-second blur in the middle of the screen, selected, so its
    /// rectangle can be drawn on the canvas. On a blur it selects that blur;
    /// with no room it beeps.
    func addBlur(atEditTime t: Double) {
        guard let source = edits.sourceTime(atEditTime: t) else { return }
        if let existing = blurs.region(at: source) {
            selectBlur(existing.id)
            return
        }
        var track = blurs
        guard let blur = track.add(at: source, duration: sources?.duration ?? edits.sourceDuration,
                                   rect: defaultBlurRect) else {
            NSSound.beep()
            return
        }
        applyBlurs(track, named: "Add Blur")
        selectBlur(blur.id)
    }

    /// A new blur covers the middle of what is on screen now, so it shows
    /// even when the recording is cropped or zoomed in.
    private var defaultBlurRect: CropRect {
        let shown = shownRect(atEditTime: playhead.time)
        let d = BlurRegion.defaultRect
        return CropRect(x: shown.x + d.x * shown.width, y: shown.y + d.y * shown.height,
                        width: d.width * shown.width, height: d.height * shown.height)
    }

    /// Delete Blur (⌫ or the inspector's button).
    func deleteSelectedBlur() {
        guard let id = selectedBlur else { return }
        var track = blurs
        track.regions.removeAll { $0.id == id }
        applyBlurs(track, named: "Delete Blur")
        selectedBlur = nil
    }

    /// The blur's start in the edited video, or nil when the cut removed it.
    func editStart(of blur: BlurRegion) -> Double? {
        edits.editRanges(fromSource: blur.start, to: blur.end).first?.lowerBound
    }

    /// The part of the recording on the canvas at `editTime`, normalized to
    /// the whole recording: the crop, narrowed by a zoom.
    func shownRect(atEditTime editTime: Double) -> CropRect {
        let crop = style.crop
        guard let source = edits.sourceTime(atEditTime: editTime) else { return crop }
        let zoom = zoomPath(for: style).view(at: source, crop: crop).rect
        return CropRect(x: crop.x + zoom.minX * crop.width, y: crop.y + zoom.minY * crop.height,
                        width: zoom.width * crop.width, height: zoom.height * crop.height)
    }
}
