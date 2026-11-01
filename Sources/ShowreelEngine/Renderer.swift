import CoreImage
import ShowreelKit

/// Where the Camera Bubble sits, how big it is, and when it is hidden,
/// for the whole recording (S-009, S-013, S-014).
public struct BubbleScene: Sendable {
    /// Bubble centers over time (normalized, top-left origin), oldest first.
    public var bubble: [EventLog.Point]
    public var fallbackCenter: CGPoint
    public var hidden: [EventLog.Range]
    /// Bubble diameter as a fraction of the output width.
    public var diameter: CGFloat
    /// Corner radius as a fraction of the diameter: 0.5 for a circle.
    public var cornerRatio: CGFloat

    public init(bubble: [EventLog.Point], fallbackCenter: CGPoint, hidden: [EventLog.Range],
                diameter: CGFloat, cornerRatio: CGFloat = 0.5) {
        self.bubble = bubble
        self.fallbackCenter = fallbackCenter
        self.hidden = hidden
        self.diameter = diameter
        self.cornerRatio = cornerRatio
    }

    private var log: EventLog {
        var log = EventLog(source: .zero)
        log.bubble = bubble
        log.cameraHidden = hidden
        return log
    }

    public func center(at t: Double) -> CGPoint { log.bubbleCenter(at: t, fallback: fallbackCenter) }
    public func isHidden(at t: Double) -> Bool { log.cameraIsHidden(at: t) }
}

/// Draws one output frame from the source frames. The preview's compositor
/// and the export share it, so they cannot drift apart.
public enum Renderer {
    /// The screen scaled to `size`, with the camera in its bubble on top
    /// unless the scene hides it at `t`. The result's extent is `size`.
    public static func frame(screen: CIImage, camera: CIImage?, at t: Double, scene: BubbleScene, size: CGSize) -> CIImage {
        var image = screen.transformed(by: CGAffineTransform(scaleX: size.width / screen.extent.width,
                                                             y: size.height / screen.extent.height))
        if let camera, !scene.isHidden(at: t) {
            image = bubble(camera, over: image, center: scene.center(at: t), diameter: scene.diameter * size.width,
                           cornerRatio: scene.cornerRatio, canvas: size)
        }
        return image.cropped(to: CGRect(origin: .zero, size: size))
    }

    /// The camera cropped to a square, mirrored, masked to a circle or rounded
    /// square, and placed at `center`.
    static func bubble(_ camera: CIImage, over base: CIImage, center: CGPoint, diameter: CGFloat,
                       cornerRatio: CGFloat, canvas: CGSize) -> CIImage {
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
