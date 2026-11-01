import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// The live Camera Bubble (S-011): a mirrored circle above every app,
/// dragged by its body. Left out of the screen capture; the camera is
/// recorded only to camera.mov.
final class CameraBubble: NSObject, NSWindowDelegate {
    static let shared = CameraBubble()
    private(set) var panel: FloatingPanel?
    /// Logs moves while recording.
    var recorder: EventRecorder?

    var size: CGFloat { Layout.bubbleSizes[1] }

    /// The bubble's center in global top-left points.
    var center: CGPoint? {
        guard let panel, panel.isVisible else { return nil }
        let f = panel.frame
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: f.midX, y: mainHeight - f.midY)
    }

    func show(session: AVCaptureSession?, near display: SCDisplay?) {
        guard let session else { return }
        if panel == nil {
            var options = FloatingPanel.Options()
            options.takesKey = false
            options.movable = true
            let panel = FloatingPanel(size: CGSize(width: size, height: size), options: options,
                                      content: CameraBubbleView(session: session, size: size))
            panel.delegate = self
            let screen = display.flatMap { d in NSScreen.screens.first { $0.displayID == d.displayID } } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: visible.maxX - size - Space.section, y: visible.minY + Space.section * 3))
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
    let session: AVCaptureSession
    let size: CGFloat

    var body: some View {
        CameraPreview(session: session)
            .frame(width: size - Space.lg, height: size - Space.lg)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Surfaces.hairline, lineWidth: 1))
            .shadow(color: Surfaces.shadow, radius: 6, y: 3)
            .frame(width: size, height: size)
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
