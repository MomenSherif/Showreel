import AVFoundation
import AppKit
import SwiftUI

/// The preview, centered and aspect-fit on the canvas backdrop. It is
/// content: no glass and no controls over it (docs/DESIGN.md, "Canvas").
struct EditorCanvas: View {
    let editor: EditorModel

    var body: some View {
        ZStack {
            Surfaces.canvasBackdrop
            if let player = editor.player {
                PlayerLayerView(player: player)
                    .padding(Space.xl)
                    .accessibilityLabel("Preview")
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

/// An AVPlayerLayer with no controls; the Editor's transport drives it.
private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerNSView {
        let view = PlayerLayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerNSView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

final class PlayerLayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer = playerLayer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
