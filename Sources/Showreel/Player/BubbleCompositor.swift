import AVFoundation
import CoreImage
import ShowreelKit

/// Draws the screen frame with the camera in a circle on top, at the Camera
/// Bubble's recorded position (S-009). The editor's renderer grows from this.
nonisolated final class BubbleInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    // @unchecked: every property is a `let` set at init.
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let screenTrack: CMPersistentTrackID
    let cameraTrack: CMPersistentTrackID?
    /// Bubble centers over time (normalized, top-left origin), oldest first.
    let bubble: [EventLog.Point]
    let fallbackCenter: CGPoint
    let hidden: [EventLog.Range]
    /// Bubble diameter as a fraction of the output width.
    let diameter: CGFloat
    /// Corner radius as a fraction of the diameter: 0.5 for a circle.
    let cornerRatio: CGFloat

    init(timeRange: CMTimeRange, screenTrack: CMPersistentTrackID, cameraTrack: CMPersistentTrackID?,
         bubble: [EventLog.Point], fallbackCenter: CGPoint, hidden: [EventLog.Range], diameter: CGFloat,
         cornerRatio: CGFloat = 0.5) {
        self.timeRange = timeRange
        self.screenTrack = screenTrack
        self.cameraTrack = cameraTrack
        self.bubble = bubble
        self.fallbackCenter = fallbackCenter
        self.hidden = hidden
        self.diameter = diameter
        self.cornerRatio = cornerRatio
        requiredSourceTrackIDs = ([screenTrack] + [cameraTrack].compactMap { $0 }).map { NSNumber(value: $0) }
    }

    private var log: EventLog {
        var log = EventLog(source: .zero)
        log.bubble = bubble
        log.cameraHidden = hidden
        return log
    }

    func center(at t: Double) -> CGPoint { log.bubbleCenter(at: t, fallback: fallbackCenter) }
    func isHidden(at t: Double) -> Bool { log.cameraIsHidden(at: t) }
}

nonisolated final class BubbleCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    // @unchecked: `context` is thread-safe; the render context is replaced
    // only through `renderContextChanged`, which AVFoundation serializes.
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var renderContext: AVVideoCompositionRenderContext?

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? BubbleInstruction,
              let screen = request.sourceFrame(byTrackID: instruction.screenTrack),
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: CocoaError(.featureUnsupported))
            return
        }
        let size = request.renderContext.size
        let extent = CGRect(origin: .zero, size: size)
        var image = CIImage(cvPixelBuffer: screen)
        image = image.transformed(by: CGAffineTransform(scaleX: size.width / image.extent.width, y: size.height / image.extent.height))

        let t = request.compositionTime.seconds
        if let id = instruction.cameraTrack, !instruction.isHidden(at: t), let camera = request.sourceFrame(byTrackID: id) {
            image = Self.bubble(CIImage(cvPixelBuffer: camera), over: image, center: instruction.center(at: t),
                                diameter: instruction.diameter * size.width, cornerRatio: instruction.cornerRatio, canvas: size)
        }
        context.render(image.cropped(to: extent), to: output, bounds: extent, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        request.finish(withComposedVideoFrame: output)
    }

    /// The camera cropped to a square, mirrored, masked to a circle or rounded
    /// square, and placed at `center`.
    static func bubble(_ camera: CIImage, over base: CIImage, center: CGPoint, diameter: CGFloat,
                       cornerRatio: CGFloat = 0.5, canvas: CGSize) -> CIImage {
        let side = min(camera.extent.width, camera.extent.height)
        let square = camera.cropped(to: CGRect(x: camera.extent.midX - side / 2, y: camera.extent.midY - side / 2, width: side, height: side))
        let scale = diameter / side
        // Image coordinates have a bottom-left origin; the log uses top-left.
        let cx = center.x * canvas.width, cy = (1 - center.y) * canvas.height
        let placed = square
            .transformed(by: CGAffineTransform(translationX: -square.extent.midX, y: -square.extent.midY))
            .transformed(by: CGAffineTransform(scaleX: -scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: cx, y: cy))
        let mask: CIImage
        if cornerRatio >= 0.5 {
            mask = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: cx, y: cy),
                "inputRadius0": diameter / 2 - 1,
                "inputRadius1": diameter / 2,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.clear,
            ])?.outputImage?.cropped(to: placed.extent) ?? placed
        } else {
            mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
                "inputExtent": CIVector(cgRect: placed.extent),
                "inputRadius": diameter * cornerRatio,
                "inputColor": CIColor.white,
            ])?.outputImage ?? placed
        }
        return placed.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: base,
            kCIInputMaskImageKey: mask,
        ])
    }
}
