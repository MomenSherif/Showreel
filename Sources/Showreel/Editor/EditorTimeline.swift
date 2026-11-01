import SwiftUI
import ShowreelKit

/// The timeline under the canvas: the transport row, then the ruler and one
/// lane per track (docs/DESIGN.md, "Timeline").
struct EditorTimeline: View {
    let editor: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            TransportRow(editor: editor)
            Divider()
            TrackArea(editor: editor)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

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

/// Split and Add Zoom, Play with the time in the middle, and the timeline
/// zoom on the trailing side.
private struct TransportRow: View {
    let editor: EditorModel

    var body: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Button("Split", systemImage: "scissors") {}
                    .help("Split at Playhead (S)")
                    .disabled(true) // S-019
                Button("Add Zoom", systemImage: "plus.magnifyingglass") {}
                    .help("Add Zoom (Z)")
                    .disabled(true) // S-032
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Space.sm) {
                Button(editor.isPlaying ? "Pause" : "Play",
                       systemImage: editor.isPlaying ? "pause.fill" : "play.fill") { editor.togglePlay() }
                    .labelStyle(.iconOnly)
                    .help(editor.isPlaying ? "Pause (Space)" : "Play (Space)")
                    .disabled(editor.player == nil)
                TransportTime(playhead: editor.playhead, duration: editor.duration)
            }

            TimelineZoomControls(editor: editor)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }
}

/// "0:00.0 / 0:42.0". Only this redraws while playing.
private struct TransportTime: View {
    let playhead: Playhead
    let duration: Double

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(TimeText.precise(playhead.time))
            Text("/").foregroundStyle(.tertiary)
            Text(TimeText.precise(duration)).foregroundStyle(.secondary)
        }
        .font(.callout.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playhead, \(TimeText.spoken(playhead.time)) of \(TimeText.spoken(duration))")
    }
}

/// − slider + and Fit, on the trailing side of the transport row.
private struct TimelineZoomControls: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: Space.sm) {
            Button("Zoom Out", systemImage: "minus") { withMotion(Motion.quick) { editor.zoom.zoomOut() } }
                .labelStyle(.iconOnly)
                .help("Zoom Out (⌘−)")
                .disabled(editor.zoom.level == 0)
            Slider(value: $editor.zoom.level, in: 0...1)
                .frame(width: Layout.zoomSliderWidth)
                .accessibilityLabel("Timeline Zoom")
            Button("Zoom In", systemImage: "plus") { withMotion(Motion.quick) { editor.zoom.zoomIn() } }
                .labelStyle(.iconOnly)
                .help("Zoom In (⌘+)")
                .disabled(editor.zoom.level == 1)
            Button("Fit") { withMotion(Motion.quick) { editor.zoom.fit() } }
                .help("Zoom to Fit (⇧Z)")
                .disabled(editor.zoom.isFit)
        }
    }
}

/// The ruler and the lanes, with the playhead over both. Zoomed in, the
/// lanes scroll sideways and the header column stays put.
private struct TrackArea: View {
    let editor: EditorModel
    @State private var position = ScrollPosition(edge: .leading)
    /// The zoom level when a pinch began.
    @State private var pinchStart: Double?

    static let rulerHeight: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            // Header column: one symbol per lane.
            VStack(spacing: 0) {
                Color.clear.frame(height: Self.rulerHeight)
                ForEach(TrackKind.allCases) { kind in
                    Image(systemName: kind.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: Layout.trackHeaderWidth, height: Layout.trackHeight)
                        .help(kind.title)
                        .accessibilityLabel(kind.title)
                }
                Spacer(minLength: 0)
            }
            .frame(width: Layout.trackHeaderWidth + Space.sm)

            GeometryReader { geo in
                let fit = TimelineScale.fit(duration: editor.duration, width: max(geo.size.width - Space.lg, 1))
                let scale = editor.zoom.scale(fitting: fit)
                let contentWidth = max(scale.x(at: editor.duration) + Space.lg, geo.size.width)
                ScrollView(.horizontal) {
                    TrackContent(editor: editor, scale: scale)
                        .frame(width: contentWidth, alignment: .leading)
                }
                .scrollPosition($position)
                .scrollIndicators(editor.zoom.isFit ? .hidden : .automatic)
                .onChange(of: editor.zoom) { centerPlayhead(scale: scale, width: geo.size.width) }
                .gesture(MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? editor.zoom.level
                        pinchStart = start
                        // Pinching to twice the size zooms in four steps.
                        editor.zoom.level = start + log2(value.magnification) * TimelineZoom.step * 4
                    }
                    .onEnded { _ in pinchStart = nil })
            }
        }
        .clipped()
    }

    /// Keeps the playhead in view when the zoom changes.
    private func centerPlayhead(scale: TimelineScale, width: CGFloat) {
        position.scrollTo(x: max(0, scale.x(at: editor.playhead.time) - width / 2)) // grid: ok follows the playback time
    }
}

/// Everything that scrolls: the ruler, the lanes, and the playhead.
private struct TrackContent: View {
    let editor: EditorModel
    let scale: TimelineScale

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Ruler(scale: scale, duration: editor.duration)
                    .frame(height: TrackArea.rulerHeight)
                ForEach(TrackKind.allCases) { kind in
                    Lane(kind: kind, editor: editor, scale: scale)
                        .frame(height: Layout.trackHeight)
                }
            }
            PlayheadLine(playhead: editor.playhead, scale: scale) { editor.jump(by: $0) }
        }
        .contentShape(Rectangle())
        // Click or drag anywhere on the ruler or lanes to scrub (S-016).
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if editor.isPlaying { editor.player?.pause() }
                editor.seek(to: scale.seconds(at: value.location.x))
            })
    }
}

/// Labeled ticks along the top, seconds or tenths depending on the scale.
private struct Ruler: View {
    let scale: TimelineScale
    let duration: Double

    var body: some View {
        Canvas { context, size in
            let label = scale.labelStep(), tick = scale.tickStep()
            let end = scale.seconds(at: size.width)
            var t = 0.0
            var index = 0
            while t <= end + 0.0001 {
                let x = scale.x(at: t)
                let isLabel = abs((t / label).rounded() - t / label) < 0.001
                let height = isLabel ? size.height : size.height / 4
                context.fill(Path(CGRect(x: x, y: size.height - height, width: 1, height: height)),
                             with: .color(Surfaces.hairline))
                if isLabel {
                    context.draw(Text(scale.label(t)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary),
                                 at: CGPoint(x: x + Space.xs, y: Space.xs), anchor: .topLeading)
                }
                index += 1
                t = Double(index) * tick
            }
        }
        .accessibilityHidden(true)
    }
}

/// One track's lane with its blocks.
private struct Lane: View {
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
private struct ClipBlock: View {
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
        .overlay(alignment: .leading) { handle(.start) }
        .overlay(alignment: .trailing) { handle(.end) }
        .offset(x: scale.x(at: start)) // grid: ok position from time
        .onTapGesture { location in
            withMotion(Motion.select) { editor.selectedSegment = segment.id }
            editor.seek(to: start + scale.seconds(at: location.x))
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

private struct Block: View {
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

/// The playhead: a contrasting line with a cap, across the ruler and lanes.
/// VoiceOver reads it as an adjustable control.
private struct PlayheadLine: View {
    let playhead: Playhead
    let scale: TimelineScale
    let jump: (Double) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Media.playhead)
                .frame(width: Space.md, height: Space.sm)
            Media.playhead.frame(width: Layout.playheadWidth)
        }
        .offset(x: scale.x(at: playhead.time) - Space.md / 2) // grid: ok follows the playback time
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Playhead")
        .accessibilityValue(TimeText.spoken(playhead.time))
        .accessibilityAdjustableAction { direction in jump(direction == .increment ? 1 : -1) }
    }
}
