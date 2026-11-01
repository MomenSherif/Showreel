import AppKit
import ScreenCaptureKit
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

/// The ScreenCaptureKit stream: screen frames (cursor hidden) and,
/// optionally, system audio, each sent to its writer.
nonisolated final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    // @unchecked: the writers are set before `start` and only read on the
    // stream's queues afterwards; `stream` is touched only from the main actor.
    private let queue = DispatchQueue(label: "showreel.capture.screen", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "showreel.capture.system-audio", qos: .userInitiated)
    private var stream: SCStream?
    private let screenWriter: TrackWriter
    private let audioWriter: TrackWriter?
    private let onError: @Sendable (Error) -> Void

    init(screenWriter: TrackWriter, audioWriter: TrackWriter?, onError: @escaping @Sendable (Error) -> Void) {
        self.screenWriter = screenWriter
        self.audioWriter = audioWriter
        self.onError = onError
    }

    @MainActor
    func start(source: CaptureSource, excluding app: SCRunningApplication?) async throws {
        let config = SCStreamConfiguration()
        let size = source.pixelSize
        config.width = size.width
        config.height = size.height
        if let area = source.area { config.sourceRect = area }
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        config.queueDepth = 6
        config.capturesAudio = audioWriter != nil
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2

        let stream = SCStream(filter: source.filter(excluding: app), configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if audioWriter != nil { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue) }
        try await stream.startCapture()
        self.stream = stream
    }

    @MainActor
    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard buffer.isValid else { return }
        let host = buffer.presentationTimeStamp.seconds
        switch type {
        case .screen:
            // Only frames with new content: idle and blank frames carry no picture.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: raw) == .complete else { return }
            screenWriter.append(buffer, host: host)
        case .audio:
            audioWriter?.append(buffer, host: host)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(error)
    }
}
