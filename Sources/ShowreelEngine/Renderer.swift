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

/// A `Style` ready to draw: the style plus the background image it names,
/// loaded once (a wallpaper or the person's image).
public struct RenderStyle: @unchecked Sendable {
    // @unchecked: CIImage is immutable and thread-safe.
    public var style: Style
    public var backgroundImage: CIImage?

    public init(style: Style, backgroundImage: CIImage? = nil) {
        self.style = style
        self.backgroundImage = backgroundImage
    }

    /// The recording edge to edge, as M1 to M3 played.
    public static let plain = RenderStyle(style: .plain)
}

/// Draws one output frame from the source frames. The preview's compositor
/// and the export share it, so they cannot drift apart.
public enum Renderer {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The background, then the screen placed with the style's padding, then
    /// the camera in its bubble on the screen unless the scene hides it at `t`.
    /// The result's extent is `size`.
    public static func frame(screen: CIImage, camera: CIImage?, at t: Double, scene: BubbleScene,
                             style: RenderStyle = .plain, size: CGSize) -> CIImage {
        let canvas = CGRect(origin: .zero, size: size)
        let crop = style.style.crop
        let screen = cropped(screen, to: crop)
        // Layout uses a top-left origin; Core Image a bottom-left one.
        let top = CanvasLayout.screenRect(content: screen.extent.size, canvas: size, padding: style.style.padding)
        let rect = CGRect(x: top.minX, y: size.height - top.maxY, width: top.width, height: top.height)
        var image = screen
            .transformed(by: CGAffineTransform(translationX: -screen.extent.minX, y: -screen.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: rect.width / screen.extent.width, y: rect.height / screen.extent.height))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        let radius = CanvasLayout.cornerRadius(style.style.rounding, canvasHeight: size.height)
        if radius > 0 { image = rounded(image, rect: rect, radius: radius) }
        if let camera, !scene.isHidden(at: t) {
            // A crop moves the bubble with its spot on the recording; its size
            // stays the same, since the camera is not part of the recording.
            image = bubble(camera, over: image, center: crop.mapClamped(scene.center(at: t)),
                           diameter: scene.diameter * rect.width, cornerRatio: scene.cornerRatio, in: rect)
        }
        if let lift = lift(style.style, rect: rect, radius: radius, canvas: size) {
            image = image.composited(over: lift)
        }
        if let background = background(style, canvas: canvas) {
            image = image.composited(over: background)
        }
        return image.cropped(to: canvas)
    }

    /// The cropped part of the recording (S-025), moved to the origin.
    static func cropped(_ screen: CIImage, to crop: CropRect) -> CIImage {
        let e = screen.extent
        guard !crop.isFull else { return screen }
        let top = crop.pixels(of: e.size)
        // Top-left crop to Core Image's bottom-left extent.
        let rect = CGRect(x: e.minX + top.minX, y: e.minY + e.height - top.maxY, width: top.width, height: top.height)
        return screen.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    /// `image` cut to a rounded rectangle; the corners become clear.
    static func rounded(_ image: CIImage, rect: CGRect, radius: CGFloat) -> CIImage {
        guard let mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: rect),
            "inputRadius": radius,
            "inputColor": CIColor.white,
        ])?.outputImage else { return image }
        return image.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])
    }

    /// The shadow or glow under the recording (S-024): its rounded shape,
    /// blurred, and for a shadow moved down a little. Sizes follow the canvas.
    static func lift(_ style: Style, rect: CGRect, radius: CGFloat, canvas: CGSize) -> CIImage? {
        let amount = min(max(style.effectAmount, 0), 1)
        guard amount > 0, style.background != .none else { return nil }
        let unit = Double(canvas.height) / 1080
        let color: CIColor, blur: Double, drop: CGFloat
        switch style.effect {
        case .shadow:
            color = CIColor(red: 0, green: 0, blue: 0, alpha: 0.25 + 0.45 * amount)
            blur = (10 + 50 * amount) * unit
            drop = CGFloat((4 + 20 * amount) * unit)
        case .glow:
            color = CIColor(red: 1, green: 1, blue: 1, alpha: 0.3 + 0.6 * amount)
            blur = (12 + 60 * amount) * unit
            drop = 0
        }
        guard let shape = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: rect),
            "inputRadius": radius,
            "inputColor": color,
        ])?.outputImage else { return nil }
        return shape.applyingGaussianBlur(sigma: blur / 2)
            .transformed(by: CGAffineTransform(translationX: 0, y: -drop))
            .cropped(to: CGRect(origin: .zero, size: canvas))
    }

    /// The canvas behind the recording, or nil for none.
    static func background(_ style: RenderStyle, canvas: CGRect) -> CIImage? {
        switch style.style.background {
        case .none:
            return nil
        case .gradient(let id):
            return gradient(GradientPreset.named(id) ?? GradientPreset.all[0], canvas: canvas)
        case .color(let rgb):
            return CIImage(color: color(rgb)).cropped(to: canvas)
        case .wallpaper, .image:
            guard let picture = style.backgroundImage else { return gradient(GradientPreset.all[0], canvas: canvas) }
            return fill(picture, canvas: canvas, blur: style.style.backgroundBlur)
        }
    }

    static func color(_ rgb: RGB) -> CIColor {
        CIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1, colorSpace: sRGB) ?? CIColor(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// From the top-left corner to the bottom-right one.
    static func gradient(_ preset: GradientPreset, canvas: CGRect) -> CIImage {
        CIFilter(name: "CISmoothLinearGradient", parameters: [
            "inputPoint0": CIVector(x: canvas.minX, y: canvas.maxY),
            "inputPoint1": CIVector(x: canvas.maxX, y: canvas.minY),
            "inputColor0": color(preset.from),
            "inputColor1": color(preset.to),
        ])?.outputImage?.cropped(to: canvas) ?? CIImage(color: color(preset.to)).cropped(to: canvas)
    }

    /// The picture scaled to cover the canvas, centered, blurred by `blur` (0...1).
    static func fill(_ picture: CIImage, canvas: CGRect, blur: Double) -> CIImage {
        let extent = picture.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return CIImage(color: .black).cropped(to: canvas) }
        let scale = max(canvas.width / extent.width, canvas.height / extent.height)
        var image = picture
            .transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: canvas.midX, y: canvas.midY))
        if blur > 0 {
            image = image.clampedToExtent()
                .applyingGaussianBlur(sigma: blur * 0.04 * Double(max(canvas.width, canvas.height)))
        }
        return image.cropped(to: canvas)
    }

    /// The camera cropped to a square, mirrored, masked to a circle or rounded
    /// square, and placed at `center`.
    static func bubble(_ camera: CIImage, over base: CIImage, center: CGPoint, diameter: CGFloat,
                       cornerRatio: CGFloat, in rect: CGRect) -> CIImage {
        let side = min(camera.extent.width, camera.extent.height)
        let square = camera.cropped(to: CGRect(x: camera.extent.midX - side / 2, y: camera.extent.midY - side / 2, width: side, height: side))
        let scale = diameter / side
        // Image coordinates have a bottom-left origin; the log uses top-left.
        let cx = rect.minX + center.x * rect.width, cy = rect.minY + (1 - center.y) * rect.height
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
