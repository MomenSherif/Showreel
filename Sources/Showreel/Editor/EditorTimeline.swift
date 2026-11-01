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

/// Split and Add Zoom, Play with the time in the middle, and the timeline
/// zoom on the trailing side.
private struct TransportRow: View {
    let editor: EditorModel

    var body: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Button("Split", systemImage: "scissors") { editor.splitAtPlayhead() }
                    .help("Split at Playhead (S)")
                    .disabled(editor.player == nil)
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
