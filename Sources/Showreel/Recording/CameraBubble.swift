import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import ShowreelKit

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

    /// Shows the bubble with the live camera. In snapshot and self-test runs, with no
    /// session, it shows a stand-in picture instead.
    func show(session: AVCaptureSession?, near display: SCDisplay?) {
        guard session != nil || Snapshot.isActive || SelfTest.requested else { return }
        if panel == nil {
            var options = FloatingPanel.Options()
            options.takesKey = false
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

    // MARK: Dragging (S-012)

    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    /// Follows the pointer in screen coordinates, so the window moving under
    /// it never feeds back into the drag.
    func drag(ended: Bool) {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
        guard let start = dragStart else { return }
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                     y: start.origin.y + mouse.y - start.mouse.y))
        if ended {
            dragStart = nil
            settle()
        }
    }

    /// Glides to the nearest corner or edge midpoint within 24 pt of the
    /// bubble, or stays put inside the screen.
    func settle(animated: Bool = true) {
        guard let panel else { return }
        let frame = panel.frame
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        // The panel includes the shadow margin; snap the circle, not the panel.
        let target = BubbleSnap.snapped(frame, in: visible, inset: Layout.snapDistance - Self.margin,
                                        distance: Layout.snapDistance)
        guard target != frame else { return }
        let duration = animated ? Motion.windowGlide : 0
        guard duration > 0 else { panel.setFrame(target, display: true); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: {
            MainActor.assumeIsolated {
                if let center = CameraBubble.shared.center { CameraBubble.shared.recorder?.bubbleMoved(to: center) }
            }
        }
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
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { _ in CameraBubble.shared.drag(ended: false) }
            .onEnded { _ in CameraBubble.shared.drag(ended: true) })
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
