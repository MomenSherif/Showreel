import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// The live Camera Bubble (S-011): a mirrored circle above every app.
/// Left out of the screen capture; the camera is recorded only to camera.mov.
final class CameraBubble: NSObject, NSWindowDelegate {
    static let shared = CameraBubble()
    private(set) var panel: FloatingPanel?
    /// Logs moves while recording.
    var recorder: EventRecorder?

    /// The bubble's diameter in points (Medium).
    var diameter: CGFloat { Layout.bubbleSizes[1] }
    /// Room around the bubble for its shadow.
    static let margin = Space.lg

    /// The bubble's center in global top-left points.
    var center: CGPoint? {
        guard let panel, panel.isVisible else { return nil }
        let f = panel.frame
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: f.midX, y: mainHeight - f.midY)
    }

    /// Shows the bubble with the live camera. In snapshot mode, with no
    /// session, it shows a stand-in picture instead.
    func show(session: AVCaptureSession?, near display: SCDisplay?) {
        guard session != nil || Snapshot.isActive else { return }
        if panel == nil {
            var options = FloatingPanel.Options()
            options.takesKey = false
            options.movable = true
            let side = diameter + 2 * Self.margin
            let panel = FloatingPanel(size: CGSize(width: side, height: side), options: options,
                                      content: CameraBubbleView(session: session, diameter: diameter))
            panel.delegate = self
            let screen = display.flatMap { d in NSScreen.screens.first { $0.displayID == d.displayID } } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                // Bottom-right corner by default.
                panel.setFrameOrigin(NSPoint(x: visible.maxX - side - Space.lg, y: visible.minY + Space.lg))
            }
            self.panel = panel
        }
        panel?.present()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    func setHidden(_ hidden: Bool) {
        panel?.animator().alphaValue = hidden ? 0 : 1
    }

    func windowDidMove(_ notification: Notification) {
        if let center { recorder?.bubbleMoved(to: center) }
    }
}

struct CameraBubbleView: View {
    let session: AVCaptureSession?
    let diameter: CGFloat

    var body: some View {
        Group {
            if let session {
                CameraPreview(session: session)
            } else {
                // Snapshot mode: no camera, so a calm stand-in.
                ZStack {
                    LinearGradient(colors: [Media.Track.zoom, Media.Track.clip], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "person.fill")
                        .font(.system(size: diameter * 0.45))
                        .foregroundStyle(Media.Track.label.opacity(0.85))
                        .offset(y: diameter * 0.1) // grid: ok proportional to the bubble
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Surfaces.hairline, lineWidth: 1))
        .shadow(color: Surfaces.shadowHover, radius: 8, y: 4)
        .padding(CameraBubble.margin)
        .accessibilityElement()
        .accessibilityLabel("Camera Bubble")
        .accessibilityHint("Drag to move it")
    }
}

/// AVCaptureVideoPreviewLayer in SwiftUI, mirrored like a mirror.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        view.layer = layer
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
