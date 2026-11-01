import AVFoundation
import CoreImage

/// One composition instruction: which tracks hold the screen and the camera,
/// and the bubble scene to draw them with.
public final class BubbleInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    // @unchecked: every property is a `let` set at init.
    public let timeRange: CMTimeRange
    public let enablePostProcessing = false
    public let containsTweening = true
    public let requiredSourceTrackIDs: [NSValue]?
    public let passthroughTrackID = kCMPersistentTrackID_Invalid

    public let screenTrack: CMPersistentTrackID
    public let cameraTrack: CMPersistentTrackID?
    public let scene: BubbleScene
    /// Source time minus composition time in this range: the scene is in
    /// source time, and a cut moves later parts earlier in the composition.
    public let sourceOffset: Double

    public init(timeRange: CMTimeRange, screenTrack: CMPersistentTrackID, cameraTrack: CMPersistentTrackID?,
                scene: BubbleScene, sourceOffset: Double = 0) {
        self.timeRange = timeRange
        self.screenTrack = screenTrack
        self.cameraTrack = cameraTrack
        self.scene = scene
        self.sourceOffset = sourceOffset
        requiredSourceTrackIDs = ([screenTrack] + [cameraTrack].compactMap { $0 }).map { NSNumber(value: $0) }
    }
}

/// The AVFoundation compositor for playback: it hands each frame's sources
/// to `Renderer` and writes the result to the output buffer.
public final class BubbleCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    // @unchecked: `context` is thread-safe; the render context is replaced
    // only through `renderContextChanged`, which AVFoundation serializes.
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var renderContext: AVVideoCompositionRenderContext?

    override public init() {}

    public let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
    ]
    public let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? BubbleInstruction,
              let screen = request.sourceFrame(byTrackID: instruction.screenTrack),
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: CocoaError(.featureUnsupported))
            return
        }
        let size = request.renderContext.size
        let t = request.compositionTime.seconds + instruction.sourceOffset
        // The camera frame is fetched only when the bubble shows.
        let camera = instruction.cameraTrack
            .flatMap { instruction.scene.isHidden(at: t) ? nil : request.sourceFrame(byTrackID: $0) }
            .map { CIImage(cvPixelBuffer: $0) }
        let image = Renderer.frame(screen: CIImage(cvPixelBuffer: screen), camera: camera, at: t,
                                   scene: instruction.scene, size: size)
        context.render(image, to: output, bounds: CGRect(origin: .zero, size: size),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        request.finish(withComposedVideoFrame: output)
    }
}
