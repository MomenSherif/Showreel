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
    /// The clicks, for click effects (S-035).
    public var clicks: ClickMarks

    public init(track: CursorTrack, sprites: [EventLog.Shape.Kind: CursorSprite], pixelsPerPoint: CGFloat, scale: Double,
                clicks: ClickMarks = ClickMarks([])) {
        self.clicks = clicks
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
              let (x, y) = place(frame.position, crop: crop, zoom: zoom, rect: rect) else { return nil }
        let height = sprite.pointHeight * pointPixels(scene, visible: visible, rect: rect)
        let k = height / sprite.image.extent.height
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

    /// A spot of the recording on the canvas (Core Image, bottom-left), or
    /// nil when the crop or the zoom leaves it out.
    static func place(_ point: CGPoint, crop: CropRect, zoom: ZoomView, rect: CGRect) -> (CGFloat, CGFloat)? {
        guard let spot = crop.map(point) else { return nil }
        // Where the spot is inside the zoomed view (top-left, 0...1).
        let q = CGPoint(x: (spot.x - zoom.rect.minX) / zoom.rect.width, y: (spot.y - zoom.rect.minY) / zoom.rect.height)
        guard (-0.1...1.1).contains(q.x), (-0.1...1.1).contains(q.y) else { return nil }
        return (rect.minX + q.x * rect.width, rect.minY + (1 - q.y) * rect.height)
    }

    /// Output pixels for one screen point of the cursor: the recording's
    /// pixels per point, its scale on the canvas with the zoom, and the cursor size.
    static func pointPixels(_ scene: CursorScene, visible: CGRect, rect: CGRect) -> CGFloat {
        scene.pixelsPerPoint * (rect.width / visible.width) * CGFloat(min(max(scene.scale, 1), 3))
    }

    /// The marks at clicks less than 400 ms old (S-035): a ripple fills a
    /// circle that grows and fades; a ring draws only its edge.
    static func clickMarks(_ scene: CursorScene, effect: Style.ClickEffect, color rgb: RGB, at t: Double, crop: CropRect,
                           zoom: ZoomView, visible: CGRect, rect: CGRect) -> CIImage? {
        guard effect != .none else { return nil }
        let full = 22 * pointPixels(scene, visible: visible, rect: rect)
        var image: CIImage?
        for mark in scene.clicks.marks(at: t) {
            guard let (x, y) = place(mark.position, crop: crop, zoom: zoom, rect: rect) else { continue }
            let grown = 1 - pow(1 - mark.progress, 3)
            let r = full * (0.35 + 0.65 * grown), fade = 1 - mark.progress
            let mark: CIImage?
            switch effect {
            case .none:
                mark = nil
            case .ripple:
                mark = disc(x: x, y: y, radius: r, color: CIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 0.45 * fade, colorSpace: sRGB))
            case .ring:
                let width = max(2, full * 0.12)
                let color = CIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 0.9 * fade, colorSpace: sRGB)
                mark = disc(x: x, y: y, radius: r, color: color).flatMap { outer in
                    disc(x: x, y: y, radius: max(r - width, 0), color: .white).map {
                        outer.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: $0])
                    }
                }
            }
            if let mark { image = image.map { mark.composited(over: $0) } ?? mark }
        }
        return image
    }

    /// A filled circle with a one-pixel soft edge.
    static func disc(x: CGFloat, y: CGFloat, radius: CGFloat, color: CIColor?) -> CIImage? {
        guard let color, radius > 0 else { return nil }
        return CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: x, y: y),
            "inputRadius0": max(radius - 1, 0),
            "inputRadius1": radius,
            "inputColor0": color,
            "inputColor1": CIColor.clear,
        ])?.outputImage?.cropped(to: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
    }
}
