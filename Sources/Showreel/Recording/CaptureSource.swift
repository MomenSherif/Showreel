import AppKit
import ScreenCaptureKit
import ShowreelEngine
import ShowreelKit

/// What the person chose in the Record Panel, resolved to ScreenCaptureKit.
struct CaptureSource {
    var kind: SourceKind
    /// For display and area: the display. For window: the window's display.
    var display: SCDisplay
    var window: SCWindow?
    /// For area: the rectangle inside the display, in display points, top-left origin.
    var area: CGRect?

    /// The recorded region in global points, top-left origin (the event log's frame).
    var globalRect: CGRect {
        if let window { return window.frame }
        if let area { return area.offsetBy(dx: display.frame.minX, dy: display.frame.minY) }
        return display.frame
    }

    var name: String {
        if let window { return [window.owningApplication?.applicationName, window.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ": ") }
        if area != nil { return "Area on \(DisplayNames.name(for: display))" }
        return DisplayNames.name(for: display)
    }

    var scale: CGFloat {
        NSScreen.screens.first { $0.displayID == display.displayID }?.backingScaleFactor ?? 2
    }

    /// Pixel size of screen.mov (even numbers, for the encoder).
    var pixelSize: (width: Int, height: Int) {
        let rect = globalRect
        return (AreaRules.evenPixels(rect.width * scale), AreaRules.evenPixels(rect.height * scale))
    }

    /// The filter. Showreel's own windows are always left out (S-003).
    func filter(excluding app: SCRunningApplication?) -> SCContentFilter {
        if let window { return SCContentFilter(desktopIndependentWindow: window) }
        return SCContentFilter(display: display, excludingApplications: app.map { [$0] } ?? [], exceptingWindows: [])
    }
}

enum DisplayNames {
    static func name(for display: SCDisplay) -> String {
        NSScreen.screens.first { $0.displayID == display.displayID }?.localizedName ?? "Display"
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// The screen whose Core Graphics frame (top-left origin) contains `rect`'s center.
    static func containing(cgRect rect: CGRect) -> NSScreen? {
        screens.first { $0.cgFrame.contains(CGPoint(x: rect.midX, y: rect.midY)) } ?? main
    }

    /// The frame in global Core Graphics coordinates (top-left origin of the main display).
    var cgFrame: CGRect {
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        return CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Converts a global top-left rect to AppKit's bottom-left coordinates.
    static func appKitRect(fromCG rect: CGRect) -> NSRect {
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

extension ScreenCapture {
    /// Starts capturing what the person chose in the Record Panel.
    func start(source: CaptureSource, excluding app: SCRunningApplication?) async throws {
        let size = source.pixelSize
        try await start(filter: source.filter(excluding: app), width: size.width, height: size.height,
                        sourceRect: source.area)
    }
}
