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
            case .zoom, .captions:
                EmptyView()
            }
        }
        .padding(.vertical, Space.xs)
        .overlay(alignment: .bottom) { Surfaces.hairline.frame(height: 1) }
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
            withMotion(Motion.select) { editor.selectedSegment = segment.id }
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

