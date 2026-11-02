import SwiftUI
import ShowreelKit

/// The kinds of lanes, top to bottom. Each has a symbol, so color is never
/// the only cue.
enum TrackKind: CaseIterable, Identifiable {
    case clip, zoom, captions, audio

    var id: Self { self }

    var title: String {
        switch self {
        case .clip: "Clip"
        case .zoom: "Zoom"
        case .captions: "Captions"
        case .audio: "Audio"
        }
    }

    var symbol: String {
        switch self {
        case .clip: "film"
        case .zoom: "plus.magnifyingglass"
        case .captions: "captions.bubble"
        case .audio: "waveform"
        }
    }

    var fill: Color {
        switch self {
        case .clip: Media.Track.clip
        case .zoom: Media.Track.zoom
        case .captions: Media.Track.caption
        case .audio: Media.Track.audio
        }
    }
}

/// One track's lane with its blocks.
struct Lane: View {
    let kind: TrackKind
    let editor: EditorModel
    let scale: TimelineScale

    var body: some View {
        ZStack(alignment: .topLeading) {
            Media.Track.lane
            switch kind {
            case .clip:
                ForEach(editor.edits.segments) { segment in
                    ClipBlock(editor: editor, segment: segment, scale: scale)
                }
            case .audio:
                if editor.project.hasMicrophone || editor.project.hasSystemAudio {
                    // Audio is cut with the clip, so it shows the same pieces.
                    ForEach(editor.edits.segments) { segment in
                        Block(kind: kind, title: editor.project.hasMicrophone ? "Microphone" : "System Audio")
                            .frame(width: max(scale.x(at: segment.length), 1))
                            .offset(x: scale.x(at: editor.edits.editStart(of: segment.id) ?? 0)) // grid: ok position from time
                    }
                }
            case .zoom:
                // A click on an empty spot adds a zoom there (S-032).
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        withMotion(Motion.select) { editor.addZoom(atEditTime: scale.seconds(at: location.x)) }
                    }
                    .help("Click to add a zoom")
                if editor.zooms.segments.isEmpty {
                    Text("Click to add a zoom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Space.sm)
                        .frame(maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
                // Zooms are kept in source time; a cut shows them in pieces.
                ForEach(editor.zooms.segments) { zoom in
                    let ranges = editor.edits.editRanges(fromSource: zoom.start, to: zoom.end)
                    ForEach(Array(ranges.enumerated()), id: \.offset) { i, range in
                        ZoomBlock(editor: editor, zoom: zoom, scale: scale,
                                  edges: (start: i == 0, end: i == ranges.count - 1))
                            .frame(width: max(scale.x(at: range.upperBound - range.lowerBound), 1))
                            .offset(x: scale.x(at: range.lowerBound)) // grid: ok position from time
                    }
                }
            case .captions:
                // Captions are kept in source time; a cut shows them in pieces (S-039).
                ForEach(editor.captions.captions) { caption in
                    let ranges = editor.edits.editRanges(fromSource: caption.start, to: caption.end)
                    ForEach(Array(ranges.enumerated()), id: \.offset) { i, range in
                        CaptionBlock(editor: editor, caption: caption, scale: scale,
                                     edges: (start: i == 0, end: i == ranges.count - 1))
                            .frame(width: max(scale.x(at: range.upperBound - range.lowerBound), 1))
                            .offset(x: scale.x(at: range.lowerBound)) // grid: ok position from time
                    }
                }
            }
        }
        .padding(.vertical, Space.xs)
        .overlay(alignment: .bottom) { Surfaces.hairline.frame(height: 1) }
    }

    /// "2×", or "2.5×" for a scale between whole numbers.
    static func scaleText(_ scale: Double) -> String {
        scale.rounded() == scale ? "\(Int(scale))×" : String(format: "%.1f×", scale)
    }
}

/// One kept piece of the clip. Click selects it; its edges trim it (S-018).
/// While an edge is dragged, the part being trimmed away is dimmed and the
/// label shows the new length; letting go closes the gap.
struct ClipBlock: View {
    let editor: EditorModel
    let segment: EditList.Segment
    let scale: TimelineScale

    private var isSelected: Bool { editor.selectedSegment == segment.id }
    /// The segment as the dragged trim would leave it.
    private var trimmed: EditList.Segment {
        editor.draft?.segments.first { $0.id == segment.id } ?? segment
    }

    var body: some View {
        let start = editor.edits.editStart(of: segment.id) ?? 0
        let kept = trimmed
        let leadingCut = kept.start - segment.start      // seconds trimmed off the start
        ZStack(alignment: .leading) {
            // The whole segment as it was, dimmed: visible only where the trim removes it.
            Radius.shape(Radius.xs)
                .fill(TrackKind.clip.fill.opacity(0.3))
            Block(kind: .clip, title: Self.length(kept.length))
                .frame(width: max(scale.x(at: kept.length), 1))
                .offset(x: scale.x(at: leadingCut)) // grid: ok position from time
                .overlay {
                    if isSelected {
                        Radius.shape(Radius.xs)
                            .strokeBorder(Palette.accent, lineWidth: Layout.selectionRing)
                            .frame(width: max(scale.x(at: kept.length), 1))
                            .offset(x: scale.x(at: leadingCut)) // grid: ok position from time
                    }
                }
        }
        .frame(width: max(scale.x(at: segment.length), 1), alignment: .leading)
        // A seam after every piece but the last, so a split shows.
        .padding(.trailing, segment.id == editor.edits.segments.last?.id ? 0 : Layout.clipSeam)
        .overlay(alignment: .leading) { handle(.start) }
        .overlay(alignment: .trailing) { handle(.end) }
        .offset(x: scale.x(at: start)) // grid: ok position from time
        .onTapGesture { location in
            withMotion(Motion.select) {
                editor.selectedSegment = segment.id
                editor.selectedZoom = nil
                editor.selectedCaption = nil
            }
            editor.seek(to: start + scale.seconds(at: location.x))
        }
        .contextMenu {
            Button("Split at Playhead") { editor.splitAtPlayhead() }
            Button("Delete Section") {
                editor.selectedSegment = segment.id
                editor.deleteSelection()
            }
            .disabled(editor.edits.segments.count < 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clip, \(Self.length(kept.length))")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// An edge handle: a grab area the full height, a visible bar when selected.
    private func handle(_ edge: EditorModel.Edge) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: Space.sm)
            .overlay {
                if isSelected {
                    Capsule().fill(Media.Track.label).frame(width: Layout.playheadWidth, height: Space.md)
                }
            }
            .contentShape(Rectangle())
            .offset(x: offset(for: edge)) // grid: ok position from time
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    editor.selectedSegment = segment.id
                    editor.previewTrim(segment.id, edge: edge, by: scale.seconds(at: value.translation.width))
                }
                .onEnded { _ in editor.commitTrim() })
            .help(edge == .start ? "Drag to trim the start" : "Drag to trim the end")
    }

    /// Handles follow the trimmed edge while dragging.
    private func offset(for edge: EditorModel.Edge) -> CGFloat {
        switch edge {
        case .start: scale.x(at: trimmed.start - segment.start)
        case .end: scale.x(at: trimmed.end - segment.end)
        }
    }

    static func length(_ seconds: Double) -> String { String(format: "%.1fs", seconds) }
}

struct Block: View {
    let kind: TrackKind
    let title: String

    var body: some View {
        Radius.shape(Radius.xs)
            .fill(kind.fill)
            .overlay {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Media.Track.label)
                    .lineLimit(1)
                    .padding(.horizontal, Space.sm)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(kind.title), \(title)")
    }
}

/// One zoom on the zoom lane. Click selects it and shows it in the
/// inspector (S-031); drag it to move it and its edges to resize it (S-032).
/// A drag stops at the next zoom. A zoom split by a cut shows in pieces;
/// only the first has the start edge and only the last the end edge.
struct ZoomBlock: View {
    let editor: EditorModel
    let zoom: ZoomSegment
    let scale: TimelineScale
    let edges: (start: Bool, end: Bool)
    @State private var dragStart: ZoomTrack?

    private var isSelected: Bool { editor.selectedZoom == zoom.id }
    private var duration: Double { editor.sources?.duration ?? editor.edits.sourceDuration }

    var body: some View {
        Block(kind: .zoom, title: Lane.scaleText(zoom.scale))
            .overlay {
                if isSelected {
                    Radius.shape(Radius.xs).strokeBorder(Palette.accent, lineWidth: Layout.selectionRing)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withMotion(Motion.select) { editor.selectZoom(zoom.id) } }
            .gesture(drag(named: "Move Zoom") { start, seconds in
                start.moving(zoom.id, by: seconds, duration: duration)
            })
            .overlay(alignment: .leading) { if edges.start { handle(.start) } }
            .overlay(alignment: .trailing) { if edges.end { handle(.end) } }
            .contextMenu {
                Button("Edit Zoom") { editor.selectZoom(zoom.id) }
                Button("Delete") {
                    editor.selectZoom(zoom.id)
                    editor.deleteSelectedZoom()
                }
            }
            .help("Zoom \(Lane.scaleText(zoom.scale)), \(ClipBlock.length(zoom.length)). Click to edit, drag to move.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Zoom, \(Lane.scaleText(zoom.scale)), \(ClipBlock.length(zoom.length))")
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { editor.selectZoom(zoom.id) }
    }

    /// A drag that previews `change(start, seconds)` and is one undo step.
    /// Global coordinates, since the block moves under the pointer.
    private func drag(named name: String, _ change: @escaping (ZoomTrack, Double) -> ZoomTrack) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? editor.zooms
                if dragStart == nil {
                    dragStart = start
                    editor.selectZoom(zoom.id)
                }
                editor.previewZooms(change(start, scale.seconds(at: value.translation.width)))
            }
            .onEnded { _ in
                if let start = dragStart { editor.commitZooms(from: start, named: name) }
                dragStart = nil
            }
    }

    /// An edge to resize by: a grab area the full height, a bar when selected.
    private func handle(_ edge: ZoomTrack.Edge) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: Space.sm)
            .overlay {
                if isSelected {
                    Capsule().fill(Media.Track.label).frame(width: Layout.playheadWidth, height: Space.md)
                }
            }
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(drag(named: "Resize Zoom") { start, seconds in
                start.resizing(zoom.id, edge: edge, by: seconds, duration: duration)
            })
            .help(edge == .start ? "Drag to change where the zoom starts" : "Drag to change where the zoom ends")
    }
}
