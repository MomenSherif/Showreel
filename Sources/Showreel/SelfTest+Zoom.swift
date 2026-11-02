import AppKit
import ShowreelEngine
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
        await cursor(editor, step: step)
    }

    /// S-034: the cursor is drawn from events.json with the system's
    /// pictures, and its size, smoothing, and idle fade are part of the style.
    static func cursor(_ editor: EditorModel, step: (() -> Void) -> Void) async {
        guard let undo = editor.undoManager else { return }
        check("the system arrow, I-beam, and pointer are loaded at least 2×",
              EventLog.Shape.Kind.allCases.allSatisfy { kind in
                  CursorSprites.system[kind].map { $0.image.extent.height >= 2 * $0.pointHeight } ?? false
              }, CursorSprites.system.map { "\($0.key): \($0.value.image.extent.height)px" }.joined(separator: ", "))
        let scene = editor.cursorScene(for: editor.style)
        // A recording where the cursor never crossed the recorded area has no cursor to draw.
        let firstSeen = editor.sources?.events?.cursor.first?.t
        check("the recording's cursor is drawn", scene != nil && firstSeen.map { scene?.track.frame(at: $0) != nil } != false)
        var big = editor.style
        big.cursorScale = 3
        big.cursorSmoothing = 1
        big.cursorHidesWhenIdle = true
        step { editor.applyStyle(big, named: "Cursor Size") }
        let saved = Style.decode(editor.project.styleData)
        check("cursor size, smoothing, and Hide When Idle are saved",
              saved.cursorScale == 3 && saved.cursorSmoothing == 1 && saved.cursorHidesWhenIdle)
        check("the drawn cursor uses the new size", editor.renderStyle(for: editor.style).cursor?.scale == 3)
        undo.undo()
        check("Undo puts the cursor size back", editor.style.cursorScale == Style().cursorScale)

        // S-035: the click effect and its color are part of the style.
        var ring = editor.style
        ring.clickEffect = .ring
        ring.clickColor = RGB(1, 0.5, 0)
        step { editor.applyStyle(ring, named: "Click Effect") }
        let clicks = Style.decode(editor.project.styleData)
        check("the click effect and its color are saved", clicks.clickEffect == .ring && clicks.clickColor == RGB(1, 0.5, 0))
        check("the recording's clicks reach the drawing",
              editor.cursorScene(for: editor.style)?.clicks == ClickMarks(editor.sources?.events?.clicks ?? []))
        undo.undo()
        check("Undo turns the click effect off", editor.style.clickEffect == .none)
        await cursorLook(editor, step: step)
    }

    /// S-055: a drawn cursor, no cursor, or the person's picture, saved with
    /// the project and drawn the same for every shape.
    static func cursorLook(_ editor: EditorModel, step: (() -> Void) -> Void) async {
        guard let undo = editor.undoManager else { return }
        check("every drawn cursor style is made", CursorArt.all.allSatisfy { CursorSprites.art[$0.id] != nil })
        var hand = editor.style
        hand.cursorLook = .art("hand")
        step { editor.applyStyle(hand, named: "Hand Cursor") }
        check("the cursor style is saved", Style.decode(editor.project.styleData).cursorLook == .art("hand"))
        let sprites = editor.cursorScene(for: editor.style)?.sprites ?? [:]
        check("the hand is drawn for the arrow, the I-beam, and the pointer",
              EventLog.Shape.Kind.allCases.allSatisfy { sprites[$0]?.image.extent == CursorSprites.art["hand"]?.image.extent })
        var none = editor.style
        none.cursorLook = .none
        step { editor.applyStyle(none, named: "No Cursor") }
        check("No Cursor draws no cursor but keeps the clicks",
              editor.cursorScene(for: editor.style).map { $0.sprites.isEmpty && $0.clicks == ClickMarks(editor.sources?.events?.clicks ?? []) } ?? false)

        // The person's own picture: copied into the project, clicking where they chose.
        let source = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("showreel-selftest-cursor.png")
        let pixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        try? pixels?.representation(using: .png, properties: [:])?.write(to: source)
        step { editor.chooseCursorPicture(source) }
        guard case .picture(let name, false) = editor.style.cursorLook else {
            check("a chosen picture becomes the cursor", false, "\(editor.style.cursorLook)")
            return
        }
        check("the picture is copied into the project", FileManager.default.fileExists(atPath: ProjectStore.file(name, of: editor.project.uuid).path))
        let picture = editor.cursorPicture(editor.style.cursorLook)
        check("a wide picture is 28 points across and clicks at its corner",
              picture.map { abs($0.pointHeight - 14) < 0.01 && $0.hotSpot == .zero } ?? false)
        step { editor.applyStyle({ var s = editor.style; s.cursorLook = .picture(name, centered: true); return s }(), named: "Cursor Click Point") }
        check("Middle clicks at the picture's middle", editor.cursorPicture(editor.style.cursorLook)?.hotSpot == CGPoint(x: 32, y: 16))
        var gone = editor.style
        gone.cursorLook = .picture("cursor-missing.png", centered: false)
        check("a missing picture falls back to the system cursor",
              CursorSprites.sprites(for: gone.cursorLook, picture: editor.cursorPicture(gone.cursorLook)).count == CursorSprites.system.count
                  && editor.cursorPicture(gone.cursorLook) == nil)
        undo.undo()
        undo.undo()
        undo.undo()
        undo.undo()
        check("Undo puts the system cursor back", editor.style.cursorLook == .system)
    }
}
