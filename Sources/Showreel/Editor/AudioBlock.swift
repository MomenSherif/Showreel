import SwiftUI
import ShowreelKit

/// One kept piece of the audio (S-042): its waveform at the tracks'
/// volumes, with muted parts flat and marked. Audio is cut with the clip, so
/// it shows the same pieces.
struct AudioBlock: View {
    let editor: EditorModel
    let segment: EditList.Segment

    var body: some View {
        let mix = editor.audio
        // Read here, not in the Canvas, so the block redraws when they load.
        let waves = editor.waveforms
        Radius.shape(Radius.xs)
            .fill(TrackKind.audio.fill)
            .overlay {
                Canvas { context, size in
                    guard size.width > 0, segment.length > 0 else { return }
                    let perPoint = segment.length / size.width
                    let mid = size.height / 2
                    let bar = Layout.waveformBar
                    // One bar every few points; its height is the loudest peak there.
                    var path = Path()
                    for x in stride(from: 0, to: size.width, by: bar * 2) {
                        let t = segment.start + Double(x) * perPoint
                        let end = t + Double(bar * 2) * perPoint
                        guard !mix.isMuted(from: t, to: end) else { continue }
                        let loud = EditorModel.loudness(of: waves, mix: mix, from: t, to: end)
                        let h = max(1, CGFloat(loud) * (size.height - 2 * Space.xs))
                        path.addRect(CGRect(x: x, y: mid - h / 2, width: bar, height: h))
                    }
                    context.fill(path, with: .color(Media.Track.label.opacity(0.85)))
                    // Muted parts: a flat line and a dimmed band.
                    for span in mix.muted where span.end > segment.start && span.start < segment.end {
                        let x0 = (max(span.start, segment.start) - segment.start) / perPoint
                        let x1 = (min(span.end, segment.end) - segment.start) / perPoint
                        let rect = CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)
                        context.fill(Path(rect), with: .color(Media.Track.mutedBand))
                        context.fill(Path(CGRect(x: x0, y: mid - 0.5, width: x1 - x0, height: 1)),
                                     with: .color(Media.Track.label.opacity(0.6)))
                    }
                }
                .clipShape(Radius.shape(Radius.xs))
                .accessibilityHidden(true)
            }
            .overlay(alignment: .leading) {
                if mix.isMuted(from: segment.start, to: segment.end) {
                    Image(systemName: "speaker.slash.fill")
                        .font(.caption)
                        .foregroundStyle(Media.Track.label)
                        .padding(.horizontal, Space.sm)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }

    private var label: String {
        let track = editor.project.hasMicrophone ? "Microphone" : "System Audio"
        let muted = editor.audio.isMuted(from: segment.start, to: segment.end) ? ", muted" : ""
        return "Audio, \(track), \(ClipBlock.length(segment.length))\(muted)"
    }
}
