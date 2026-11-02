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
    /// The recorded cursor, for zooms that follow it (S-031).
    public var cursor: CursorPath

    public init(bubble: [EventLog.Point], fallbackCenter: CGPoint, hidden: [EventLog.Range],
                diameter: CGFloat, cornerRatio: CGFloat = 0.5, cursor: CursorPath = CursorPath()) {
        self.cursor = cursor
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

/// Everything the editor changes without rebuilding the player: the style,
/// the background image it names (loaded once), and the zooms.
public struct RenderStyle: @unchecked Sendable {
    // @unchecked: CIImage is immutable and thread-safe.
    public var style: Style
    public var backgroundImage: CIImage?
    /// In source time, like the scene (S-030).
    public var zooms: ZoomTrack
    /// The camera moving through `zooms` (S-033). Without one, it is worked
    /// out from `zooms` at the style's speed, with no cursor to follow.
    public var zoomPath: ZoomPath
    /// The cursor to draw (S-034). Nil draws none.
    public var cursor: CursorScene?
    /// In source time (S-041). Drawn on top of everything, in `style.captions`' look.
    public var captions: CaptionTrack
    /// In source time (S-048). Drawn into the recording, before crop and zoom.
    public var blurs: BlurTrack

    public init(style: Style, backgroundImage: CIImage? = nil, zooms: ZoomTrack = ZoomTrack(), zoomPath: ZoomPath? = nil,
                cursor: CursorScene? = nil, captions: CaptionTrack = CaptionTrack(), blurs: BlurTrack = BlurTrack()) {
        self.blurs = blurs
        self.cursor = cursor
        self.captions = captions
        self.style = style
        self.backgroundImage = backgroundImage
        self.zooms = zooms
        self.zoomPath = zoomPath ?? ZoomPath(track: zooms, duration: zooms.segments.last?.end ?? 0, speed: style.zoomSpeed)
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
        // A blur hides part of the recording itself, so crops, zooms, and the
        // frame carry it along; the cursor is drawn over it (S-048).
        let screen = cropped(blurred(screen, by: style.blurs.region(at: t)), to: crop)
        // Layout uses a top-left origin; Core Image a bottom-left one.
        let chrome = CanvasLayout.chrome(for: style.style, canvasHeight: size.height)
        let top = CanvasLayout.screenRect(content: screen.extent.size, canvas: size, padding: style.style.padding, chrome: chrome)
        let rect = CGRect(x: top.minX, y: size.height - top.maxY, width: top.width, height: top.height)
        // A zoom shows part of the recording in the same place (S-030); the
        // frame, background, and camera stay put.
        let zoom = style.zoomPath.view(at: t, crop: crop)
        let visible = visibleRect(of: screen.extent, zoom)
        var image = screen
            .transformed(by: CGAffineTransform(translationX: -visible.minX, y: -visible.minY))
            .transformed(by: CGAffineTransform(scaleX: rect.width / visible.width, y: rect.height / visible.height))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        // Click marks under the cursor, both clipped to the recording (S-034, S-035).
        var drawn = false
        if let scene = style.cursor {
            if let marks = clickMarks(scene, effect: style.style.clickEffect, color: style.style.clickColor, at: t, crop: crop,
                                      zoom: zoom, visible: visible, rect: rect) {
                image = marks.composited(over: image)
                drawn = true
            }
            if let pointer = cursor(scene, at: t, crop: crop, zoom: zoom, visible: visible, rect: rect) {
                image = pointer.composited(over: image)
                drawn = true
            }
        }
        if drawn || zoom.isZoomed { image = image.cropped(to: rect) }
        let radius = CanvasLayout.cornerRadius(style.style.rounding, canvasHeight: size.height)
        let device = DeviceChrome.parts(for: style.style, rect: rect, radius: radius, canvas: size)
        if let mask = device.screenMask { image = masked(image, by: mask) }
        let look = style.style
        if let camera, look.cameraVisible, !scene.isHidden(at: t) {
            // A position dragged in the editor holds for the whole video (S-028).
            // Otherwise a crop moves the bubble with its spot on the recording;
            // its size stays, since the camera is not part of the recording.
            let center = look.cameraPosition.map { CGPoint(x: $0.x, y: $0.y) } ?? crop.mapClamped(scene.center(at: t))
            let diameter = scene.diameter * rect.width * CGFloat(min(max(look.cameraScale, 0.5), 2))
            image = bubble(camera, over: image, center: center, diameter: diameter,
                           cornerRatio: look.cameraShape.map { CGFloat($0.cornerRatio) } ?? scene.cornerRatio,
                           border: CGFloat(min(max(look.cameraBorder, 0), 1)) * diameter * 0.05,
                           shadow: min(max(look.cameraShadow, 0), 1), in: rect)
        }
        if let behind = device.behind { image = image.composited(over: behind) }
        if let lift = lift(style.style, rect: device.outer, radius: device.outerRadius, canvas: size) {
            image = image.composited(over: lift)
        }
        if let background = background(style, canvas: canvas) {
            image = image.composited(over: background)
        }
        // Captions sit on the canvas, not the recording: zooms and crops leave them be.
        if let caption = CaptionPainter.image(for: style.captions, style: look.captions, at: t, canvas: size) {
            image = caption.composited(over: image)
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

    /// The recording with `blur`'s rectangle blurred or pixelated, in the
    /// recording's own pixels, so the preview and the export look the same.
    static func blurred(_ screen: CIImage, by blur: BlurRegion?) -> CIImage {
        guard let blur else { return screen }
        let extent = screen.extent
        let area = blur.pixelRect(in: extent)
        guard area.width >= 1, area.height >= 1 else { return screen }
        let long = Double(max(extent.width, extent.height))
        let hidden: CIImage
        switch blur.style {
        case .blur:
            // Clamped to the area, so the edges blur the hidden pixels, not
            // the ones around them, and nothing readable bleeds in.
            hidden = screen.cropped(to: area).clampedToExtent().applyingGaussianBlur(sigma: blur.blurSigma(long: long))
        case .pixelate:
            hidden = screen.cropped(to: area).clampedToExtent().applyingFilter("CIPixellate", parameters: [
                kCIInputCenterKey: CIVector(x: area.minX, y: area.minY),
                kCIInputScaleKey: blur.blockSize(long: long),
            ])
        }
        return hidden.cropped(to: area).composited(over: screen)
    }

    /// The part of `extent` a zoom shows, in Core Image's bottom-left coordinates.
    static func visibleRect(of extent: CGRect, _ zoom: ZoomView) -> CGRect {
        guard zoom.isZoomed else { return extent }
        let r = zoom.rect
        return CGRect(x: extent.minX + r.minX * extent.width, y: extent.minY + (1 - r.maxY) * extent.height,
                      width: r.width * extent.width, height: r.height * extent.height)
    }

    /// `image` where `mask` is white; clear elsewhere.
    static func masked(_ image: CIImage, by mask: CIImage) -> CIImage {
        image.applyingFilter("CIBlendWithAlphaMask", parameters: [
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
        case .blend(let id):
            return blend(BlendPreset.named(id) ?? BlendPreset.all[0], canvas: canvas)
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

    /// A blend (docs/GLOSSARY.md): the base color with each glow over it, a
    /// Gaussian falloff from its spot, so there are no edges or bands. Sizes
    /// follow the canvas's longer side, so every aspect ratio and size looks alike.
    public static func blend(_ preset: BlendPreset, canvas: CGRect) -> CIImage {
        let long = max(canvas.width, canvas.height)
        var image = CIImage(color: color(preset.base)).cropped(to: canvas)
        for glow in preset.glows {
            let c = color(glow.color)
            guard let light = CIFilter(name: "CIGaussianGradient", parameters: [
                "inputCenter": CIVector(x: canvas.minX + glow.x * canvas.width, y: canvas.maxY - glow.y * canvas.height),
                "inputColor0": c,
                "inputColor1": CIColor(red: c.red, green: c.green, blue: c.blue, alpha: 0, colorSpace: sRGB) ?? .clear,
                "inputRadius": glow.radius * long,
            ])?.outputImage else { continue }
            image = light.cropped(to: canvas).composited(over: image)
        }
        return image
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
    /// square, and placed at `center` (normalized to `rect`, top-left). A white
    /// ring of `border` pixels and a soft shadow (0...1) go under it.
    static func bubble(_ camera: CIImage, over base: CIImage, center: CGPoint, diameter: CGFloat,
                       cornerRatio: CGFloat, border: CGFloat = 0, shadow: Double = 0, in rect: CGRect) -> CIImage {
        let side = min(camera.extent.width, camera.extent.height)
        let square = camera.cropped(to: CGRect(x: camera.extent.midX - side / 2, y: camera.extent.midY - side / 2, width: side, height: side))
        let scale = diameter / side
        // Image coordinates have a bottom-left origin; the log uses top-left.
        let cx = rect.minX + center.x * rect.width, cy = rect.minY + (1 - center.y) * rect.height
        let placed = square
            .transformed(by: CGAffineTransform(translationX: -square.extent.midX, y: -square.extent.midY))
            .transformed(by: CGAffineTransform(scaleX: -scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: cx, y: cy))
        let mask = shape(cx: cx, cy: cy, diameter: diameter, cornerRatio: cornerRatio, color: .white) ?? placed
        var under = base
        if shadow > 0, let shade = shape(cx: cx, cy: cy, diameter: diameter, cornerRatio: cornerRatio,
                                         color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.25 + 0.4 * shadow)) {
            under = shade.applyingGaussianBlur(sigma: Double(diameter) * (0.03 + 0.05 * shadow))
                .transformed(by: CGAffineTransform(translationX: 0, y: -diameter * 0.03 * shadow))
                .composited(over: under)
        }
        if border > 0, let ring = shape(cx: cx, cy: cy, diameter: diameter + 2 * border,
                                        cornerRatio: cornerRatio, color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.95)) {
            under = ring.composited(over: under)
        }
        return placed.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: under,
            kCIInputMaskImageKey: mask,
        ])
    }

    /// A filled circle (cornerRatio 0.5) or rounded square centered at cx, cy.
    static func shape(cx: CGFloat, cy: CGFloat, diameter: CGFloat, cornerRatio: CGFloat, color: CIColor) -> CIImage? {
        let box = CGRect(x: cx - diameter / 2, y: cy - diameter / 2, width: diameter, height: diameter)
        if cornerRatio >= 0.5 {
            return CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: cx, y: cy),
                "inputRadius0": diameter / 2 - 1,
                "inputRadius1": diameter / 2,
                "inputColor0": color,
                "inputColor1": CIColor.clear,
            ])?.outputImage?.cropped(to: box)
        }
        return CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: box),
            "inputRadius": diameter * cornerRatio,
            "inputColor": color,
        ])?.outputImage
    }

}
