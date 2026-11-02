import AVFoundation
import AppKit
import SwiftUI
import ShowreelKit

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
                if editor.project.hasCamera, editor.style.cameraVisible {
                    CameraHandle(editor: editor, playhead: editor.playhead)
                }
                if editor.selectedBlur != nil {
                    BlurHandle(editor: editor, playhead: editor.playhead)
                }
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

/// Drag the camera on the canvas (S-028): the position holds for the whole
/// video. A ring shows where it can be grabbed while the pointer is over it.
private struct CameraHandle: View {
    let editor: EditorModel
    let playhead: Playhead
    @State private var dragStart: Style?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            if let canvas = editor.canvasGeometry(in: geo.size, inset: Space.xl),
               let center = editor.cameraCenter(at: playhead.time) {
                let diameter = editor.cameraDiameter * canvas.screen.width
                let point = CGPoint(x: canvas.screen.minX + center.x * canvas.screen.width,
                                    y: canvas.screen.minY + center.y * canvas.screen.height)
                Circle()
                    .strokeBorder(Palette.accent, lineWidth: Layout.selectionRing)
                    .opacity(hovering || dragStart != nil ? 1 : 0)
                    .contentShape(Circle())
                    .frame(width: diameter, height: diameter)
                    .position(point) // grid: ok follows the camera
                    .onHover { hovering = $0 }
                    .pointerStyle(dragStart == nil ? .grabIdle : .grabActive)
                    .gesture(DragGesture(coordinateSpace: .local)
                        .onChanged { value in
                            let start = dragStart ?? editor.style
                            dragStart = start
                            var style = editor.style
                            style.cameraPosition = Style.Point(
                                x: min(max((value.location.x - canvas.screen.minX) / canvas.screen.width, 0), 1),
                                y: min(max((value.location.y - canvas.screen.minY) / canvas.screen.height, 0), 1))
                            editor.previewStyle(style)
                        }
                        .onEnded { _ in
                            if let start = dragStart { editor.commitStyle(from: start, named: "Move Camera") }
                            dragStart = nil
                        })
                    .help("Drag to move the camera for the whole video")
                    .accessibilityLabel("Camera")
                    .accessibilityHint("Drag to move the camera for the whole video")
            }
        }
    }
}

