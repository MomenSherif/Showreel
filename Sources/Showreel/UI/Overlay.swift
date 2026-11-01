import AppKit
import SwiftUI

/// The one panel builder for Showreel's floating chrome: the Record Panel,
/// Countdown, Recording Controls, Camera Bubble, and area selector
/// (docs/DESIGN.md, "Archetype"). Borderless, clear, never in the Window menu.
final class FloatingPanel: NSPanel {
    struct Options {
        var level: NSWindow.Level = .floating
        /// Takes keyboard focus (Escape, Return, Tab) when shown.
        var takesKey = true
        var movable = false
        var ignoresMouse = false
        /// Escape closes the panel.
        var onCancel: (() -> Void)?
    }

    private let options: Options

    init(size: CGSize, options: Options, content: some View) {
        self.options = options
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = options.level
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // glass and content draw their own shadows
        isMovableByWindowBackground = options.movable
        ignoresMouseEvents = options.ignoresMouse
        isExcludedFromWindowsMenu = true
        // Never in a recording or a screenshot of the screen. Snapshot mode
        // needs to capture the panel itself, so it allows reading.
        sharingType = Snapshot.isActive ? .readOnly : .none
        let host = NSHostingView(rootView: content.themed())
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { options.takesKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        if let onCancel = options.onCancel { onCancel() } else { orderOut(nil) }
    }

    /// Shows the panel, focused when it takes keys, without activating the
    /// app being recorded unless `activate` is true (the global shortcut).
    func present(activate: Bool = false) {
        if activate { NSApp.activate() }
        orderFrontRegardless()
        if options.takesKey { makeKey() }
    }

    func resize(to size: CGSize) {
        var frame = self.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        setFrame(frame, display: true)
    }
}
