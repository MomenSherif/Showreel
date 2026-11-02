import CoreImage
import ShowreelKit

/// One system cursor picture, drawn large once by the app (S-034).
public struct CursorSprite: @unchecked Sendable {
    // @unchecked: CIImage is immutable and thread-safe.
    /// The picture, origin at zero.
    public var image: CIImage
    /// The click point, in the picture's pixels from its top-left corner.
    public var hotSpot: CGPoint
    /// The picture's height on screen, in points.
    public var pointHeight: CGFloat

    public init(image: CIImage, hotSpot: CGPoint, pointHeight: CGFloat) {
        self.image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        self.hotSpot = hotSpot
        self.pointHeight = pointHeight
    }
}

/// Everything needed to draw the cursor over a recording (S-034).
public struct CursorScene: Sendable {
    public var track: CursorTrack
    public var sprites: [EventLog.Shape.Kind: CursorSprite]
    /// Recorded pixels per screen point: 2 on a Retina display.
    public var pixelsPerPoint: CGFloat
    /// 1...3 times the size it had on screen.
    public var scale: Double

    public init(track: CursorTrack, sprites: [EventLog.Shape.Kind: CursorSprite], pixelsPerPoint: CGFloat, scale: Double) {
        self.track = track
        self.sprites = sprites
        self.pixelsPerPoint = pixelsPerPoint
        self.scale = scale
    }
}

extension Renderer {
    /// The cursor at `t` over the recording drawn in `rect`, or nil when it
    /// does not show. `visible` is the part of the (cropped) recording in
    /// `rect`, in its pixels; `zoom` and `crop` place the cursor on it.
    static func cursor(_ scene: CursorScene, at t: Double, crop: CropRect, zoom: ZoomView,
                       visible: CGRect, rect: CGRect) -> CIImage? {
        guard let frame = scene.track.frame(at: t), frame.opacity > 0,
              let sprite = scene.sprites[frame.shape] ?? scene.sprites[.arrow],
              let spot = crop.map(frame.position) else { return nil }
        // Where the spot is inside the zoomed view (top-left, 0...1).
        let q = CGPoint(x: (spot.x - zoom.rect.minX) / zoom.rect.width, y: (spot.y - zoom.rect.minY) / zoom.rect.height)
        guard (-0.1...1.1).contains(q.x), (-0.1...1.1).contains(q.y) else { return nil }
        // Output pixels per recorded pixel, the zoom included.
        let magnify = rect.width / visible.width
        let height = sprite.pointHeight * scene.pixelsPerPoint * magnify * CGFloat(min(max(scene.scale, 1), 3))
        let k = height / sprite.image.extent.height
        let x = rect.minX + q.x * rect.width, y = rect.minY + (1 - q.y) * rect.height
        var image = sprite.image
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: k, kCIInputAspectRatioKey: 1])
        image = image.transformed(by: CGAffineTransform(translationX: x - sprite.hotSpot.x * k - image.extent.minX,
                                                        y: y - (sprite.image.extent.height - sprite.hotSpot.y) * k - image.extent.minY))
        if frame.opacity < 1 {
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(frame.opacity)),
            ])
        }
        return image
    }
}
