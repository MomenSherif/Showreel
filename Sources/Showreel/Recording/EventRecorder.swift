import AppKit
import ApplicationServices
import ShowreelEngine
import ShowreelKit

/// Logs the cursor (60 Hz), clicks, key presses, and Camera Bubble moves
/// into an `EventLog`, in recording time (S-007, S-012, S-014).
/// Key presses need Accessibility; without it the log has no keys.
final class EventRecorder {
    private(set) var log: EventLog
    private let timeline: Timeline
    private var timer: Timer?
    private var monitors: [Any] = []
    private var lastCursor: CGPoint?
    private var hidden = HiddenRanges()
    private var lastCaretLookup = -Double.infinity

    init(source: CGRect, timeline: Timeline) {
        log = EventLog(source: source)
        self.timeline = timeline
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleCursor() }
        }
        timer?.tolerance = 0.002
        RunLoop.main.add(timer!, forMode: .common)
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.click(type) }
        }) { monitors.append(clicks) }
        if AXIsProcessTrusted(), let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let code = event.keyCode
            MainActor.assumeIsolated { self?.key(code) }
        }) { monitors.append(keys) }
    }

    /// Stops logging and closes an open hidden range at `end`.
    func stop(at end: Double) -> EventLog {
        timer?.invalidate()
        timer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        hidden.close(at: end)
        log.cameraHidden = hidden.ranges
        return log
    }

    private var now: Double? { timeline.mediaTime(at: Timeline.hostNow) }

    /// Like `now`, but while paused it is the moment the pause began, so a
    /// bubble moved or hidden during a pause applies from where the video resumes.
    private var nowOrPausePoint: Double? {
        now ?? (timeline.isStarted ? timeline.elapsed() : nil)
    }

    /// The mouse in global top-left coordinates.
    private var mouse: CGPoint {
        let p = NSEvent.mouseLocation
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: p.x, y: mainHeight - p.y)
    }

    private func sampleCursor() {
        guard let t = now else { return }
        let point = mouse
        guard point != lastCursor, let n = log.normalized(point) else { return }
        lastCursor = point
        log.cursor.append(.init(t: t, x: n.x, y: n.y))
    }

    private func click(_ type: NSEvent.EventType) {
        guard let t = now, let n = log.normalized(mouse) else { return }
        let button: EventLog.Click.Button = switch type {
        case .leftMouseDown: .left
        case .rightMouseDown: .right
        default: .other
        }
        log.clicks.append(.init(t: t, x: n.x, y: n.y, button: button))
    }

    private func key(_ code: UInt16) {
        guard let t = now else { return }
        log.keys.append(.init(t: t, keyCode: code))
        // Where the typing goes, for the zoom on it (S-030). At most 4 a second.
        guard t - lastCaretLookup >= 0.25 else { return }
        lastCaretLookup = t
        Task { [weak self] in
            guard let point = await Caret.location(), let self, let n = self.log.normalized(point) else { return }
            self.log.caret.append(.init(t: t, x: n.x, y: n.y))
        }
    }

    /// The Camera Bubble's center in global top-left points.
    func bubbleMoved(to center: CGPoint) {
        guard let t = nowOrPausePoint else { return }
        let rect = log.source
        guard rect.width > 0, rect.height > 0 else { return }
        log.bubble.append(.init(t: t, x: (center.x - rect.minX) / rect.width, y: (center.y - rect.minY) / rect.height))
    }

    /// ⌃⌥⌘C while recording (S-014).
    func cameraHidden(_ isHidden: Bool) {
        guard let t = nowOrPausePoint else { return }
        if isHidden { hidden.hide(at: t) } else { hidden.show(at: t) }
    }
}

/// The text caret of the focused app, through Accessibility.
enum Caret {
    /// The caret's center in global top-left points, or nil when the focused
    /// element has no text caret or does not answer within 0.1 seconds.
    @concurrent nonisolated static func location() async -> CGPoint? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.1)
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        // Some apps answer with an empty rect at the origin: no caret.
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0, rect.origin != .zero else { return nil }
        return CGPoint(x: rect.midX, y: rect.midY)
    }
}
