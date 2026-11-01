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

            HStack(spacing: Space.sm) {
                Button("Zoom Out", systemImage: "minus") {}
                    .labelStyle(.iconOnly)
                    .help("Zoom Out (⌘−)")
                Slider(value: .constant(0), in: 0...1)
                    .frame(width: 96)
                    .accessibilityLabel("Timeline Zoom")
                Button("Zoom In", systemImage: "plus") {}
                    .labelStyle(.iconOnly)
                    .help("Zoom In (⌘+)")
                Button("Fit") {}
                    .help("Zoom to Fit (⇧Z)")
            }
            .disabled(true) // S-017
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

/// The ruler and the lanes, with the playhead over both.
private struct TrackArea: View {
    let editor: EditorModel

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
                let width = max(geo.size.width - Space.lg, 1)
                let scale = TimelineScale.fit(duration: editor.duration, width: width)
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        Ruler(scale: scale, duration: editor.duration)
                            .frame(height: Self.rulerHeight)
                        ForEach(TrackKind.allCases) { kind in
                            Lane(kind: kind, editor: editor, scale: scale)
                                .frame(height: Layout.trackHeight)
                        }
                    }
                    PlayheadLine(playhead: editor.playhead, scale: scale)
                }
                .contentShape(Rectangle())
                // Click or drag anywhere on the ruler or lanes to scrub (S-016).
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if editor.isPlaying { editor.player?.pause() }
                        editor.seek(to: scale.seconds(at: value.location.x))
                    })
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Timeline")
                .accessibilityValue("Playhead at \(TimeText.spoken(editor.playhead.time))")
                .accessibilityAdjustableAction { direction in
                    editor.jump(by: direction == .increment ? 1 : -1)
                }
            }
        }
        .clipped()
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
        ZStack(alignment: .leading) {
            Media.Track.lane
            if let block {
                Block(kind: kind, title: block.title)
                    .frame(width: max(scale.x(at: block.length), 1))
            }
        }
        .padding(.vertical, Space.xs)
        .overlay(alignment: .bottom) { Surfaces.hairline.frame(height: 1) }
    }

    /// What this lane shows today: the clip, and the audio when there is any.
    private var block: (title: String, length: Double)? {
        let project = editor.project
        switch kind {
        case .clip:
            return ("\(String(format: "%.1f", editor.duration))s", editor.duration)
        case .audio:
            guard project.hasMicrophone || project.hasSystemAudio else { return nil }
            return (project.hasMicrophone ? "Microphone" : "System Audio", editor.duration)
        case .zoom, .captions:
            return nil
        }
    }
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
private struct PlayheadLine: View {
    let playhead: Playhead
    let scale: TimelineScale

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Media.playhead)
                .frame(width: Space.md, height: Space.sm)
            Media.playhead.frame(width: Layout.playheadWidth)
        }
        .offset(x: scale.x(at: playhead.time) - Space.md / 2) // grid: ok follows the playback time
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
