import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftData
import SwiftUI
import ShowreelEngine
import ShowreelKit

/// Self-test checks for the Camera Bubble (M2).
extension SelfTest {
    /// S-012: a bubble dropped near a corner glides into it; one dropped in
    /// the open stays where it is; moves are logged in source coordinates.
    static func bubbleSnap() {
        let bubble = CameraBubble.shared
        bubble.show(session: nil, near: nil)
        guard let panel = bubble.panel, let visible = panel.screen?.visibleFrame else {
            check("shows the Camera Bubble", false)
            return
        }
        let side = panel.frame.width
        let inset = Layout.snapDistance - CameraBubble.margin
        panel.setFrameOrigin(NSPoint(x: visible.minX + inset + 15, y: visible.maxY - side - inset - 10))
        bubble.settle(animated: false)
        check("a bubble dropped near the top-left corner snaps into it",
              panel.frame.origin == NSPoint(x: visible.minX + inset, y: visible.maxY - side - inset), "\(panel.frame.origin)")
        let free = NSPoint(x: visible.midX - 200, y: visible.midY - 150)
        panel.setFrameOrigin(free)
        bubble.settle(animated: false)
        check("a bubble dropped in the open stays there", panel.frame.origin == free)

        let timeline = Timeline()
        let source = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let events = EventRecorder(source: source, timeline: timeline)
        timeline.begin(at: Timeline.hostNow - 1)
        events.bubbleMoved(to: CGPoint(x: 250, y: 400))
        let move = events.stop(at: 2).bubble.first
        check("a bubble move is logged in source coordinates with its time",
              move?.x == 0.25 && move?.y == 0.8 && (move?.t ?? 0) >= 1, "\(String(describing: move))")
        bubbleStyle(bubble, panel: panel)
        bubble.hide()
        hideCamera()
    }

    /// S-014: hiding the camera while recording is logged as a range, and the
    /// player leaves the camera out for that range.
    static func hideCamera() {
        let timeline = Timeline()
        let events = EventRecorder(source: CGRect(x: 0, y: 0, width: 100, height: 100), timeline: timeline)
        timeline.begin(at: Timeline.hostNow - 2)   // two seconds in
        events.cameraHidden(true)
        timeline.pause()
        timeline.resume(at: Timeline.hostNow + 0)
        let log = events.stop(at: 5)               // still hidden when it stops
        let range = log.cameraHidden.first
        check("hiding the camera logs a range that ends at Stop",
              log.cameraHidden.count == 1 && abs((range?.start ?? 0) - 2) < 0.2 && range?.end == 5, "\(log.cameraHidden)")
        let scene = BubbleScene(bubble: [], fallbackCenter: .zero, hidden: log.cameraHidden, diameter: 0.1)
        check("the player hides the camera in that range", scene.isHidden(at: 3) && !scene.isHidden(at: 1))
        let paused = Timeline()
        let pausedEvents = EventRecorder(source: CGRect(x: 0, y: 0, width: 100, height: 100), timeline: paused)
        paused.begin(at: Timeline.hostNow - 3)
        paused.pause(at: Timeline.hostNow - 1)     // paused at 2 s
        pausedEvents.cameraHidden(true)
        let pausedLog = pausedEvents.stop(at: 4)
        check("hiding the camera while paused counts from the pause",
              abs((pausedLog.cameraHidden.first?.start ?? -1) - 2) < 0.2, "\(pausedLog.cameraHidden)")
        let menu = NSApp.mainMenu?.item(withTitle: "Record")?.submenu?.items.map(\.title) ?? []
        check("the Record menu has Hide Camera Bubble", menu.contains("Hide Camera Bubble"), menu.joined(separator: ", "))
    }

    /// S-013: size and shape change the bubble and are remembered.
    static func bubbleStyle(_ bubble: CameraBubble, panel: NSWindow) {
        let style = BubbleStyle.shared
        let saved = (style.size, style.shape)
        defer { style.size = saved.0; style.shape = saved.1 }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        style.size = 2
        check("Large makes the bubble 240 pt", panel.frame.width == Layout.bubbleSizes[2] + 2 * CameraBubble.margin)
        check("resizing keeps the bubble's center", abs(panel.frame.midX - center.x) < 1 && abs(panel.frame.midY - center.y) < 1)
        check("the size is remembered", UserDefaults.standard.integer(forKey: "bubble.size") == 2)
        style.shape = .roundedSquare
        check("the shape is remembered", UserDefaults.standard.string(forKey: "bubble.shape") == "roundedSquare")
        bubble.showControls()
        check("hover shows the size and shape controls", bubble.controls?.parent === panel)
    }
}
