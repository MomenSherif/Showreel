import Foundation

/// A color in sRGB, 0...1 per channel. Content color (it ends up in the
/// video), not a UI color.
public struct RGB: Codable, Equatable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    /// 0xRRGGBB.
    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}

/// A two-color gradient for the background (S-022).
public struct GradientPreset: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let from: RGB
    public let to: RGB

    /// The presets, in the order of the inspector's grid.
    public static let all: [GradientPreset] = [
        .init(id: "dusk", name: "Dusk", from: RGB(hex: 0x7AA2F7), to: RGB(hex: 0x5B3CC4)),
        .init(id: "violet", name: "Violet", from: RGB(hex: 0xC471F5), to: RGB(hex: 0x6A3DE8)),
        .init(id: "ocean", name: "Ocean", from: RGB(hex: 0x4FACFE), to: RGB(hex: 0x0061C2)),
        .init(id: "lagoon", name: "Lagoon", from: RGB(hex: 0x43E97B), to: RGB(hex: 0x1F8EA3)),
        .init(id: "mint", name: "Mint", from: RGB(hex: 0xA8EDEA), to: RGB(hex: 0x4FB3A9)),
        .init(id: "sunrise", name: "Sunrise", from: RGB(hex: 0xFDCB82), to: RGB(hex: 0xF0657A)),
        .init(id: "peach", name: "Peach", from: RGB(hex: 0xFFD3A5), to: RGB(hex: 0xFD6585)),
        .init(id: "ember", name: "Ember", from: RGB(hex: 0xF6D365), to: RGB(hex: 0xE5532D)),
        .init(id: "rose", name: "Rose", from: RGB(hex: 0xF9A8D4), to: RGB(hex: 0xBE3B8A)),
        .init(id: "forest", name: "Forest", from: RGB(hex: 0x96C93D), to: RGB(hex: 0x00704A)),
        .init(id: "slate", name: "Slate", from: RGB(hex: 0x8E9EAB), to: RGB(hex: 0x3B4754)),
        .init(id: "graphite", name: "Graphite", from: RGB(hex: 0x4B4F58), to: RGB(hex: 0x16181D)),
        .init(id: "midnight", name: "Midnight", from: RGB(hex: 0x3A3F9E), to: RGB(hex: 0x0B0D2C)),
        .init(id: "paper", name: "Paper", from: RGB(hex: 0xFAFAF7), to: RGB(hex: 0xD9D8D2)),
    ]

    public static func named(_ id: String) -> GradientPreset? { all.first { $0.id == id } }
}

/// How the recording is presented on the canvas (M4). Stored as JSON in
/// `Project.styleData`. Every field decodes with a default, so styles saved
/// by older versions keep loading when fields are added.
public struct Style: Codable, Equatable, Sendable {
    public enum Background: Codable, Equatable, Hashable, Sendable {
        /// No background: the recording fills the canvas.
        case none
        case gradient(String)
        case color(RGB)
        /// A macOS wallpaper, by file path. Missing files show the default gradient.
        case wallpaper(String)
        /// The person's own image, copied into the project folder (file name).
        case image(String)
    }

    public var background: Background = .gradient(GradientPreset.all[0].id)
    /// Blur for wallpapers and images, 0...1.
    public var backgroundBlur: Double = 0
    /// Space around the recording, as a share of the canvas's shorter side, 0...0.3.
    public var padding: Double = 0.06
    /// Corner radius of the recording, in pixels of a 1080-pixel-tall canvas, 0...40.
    public var rounding: Double = 12

    /// What lifts the recording off the background (S-024).
    public enum Effect: String, Codable, CaseIterable, Sendable { case shadow, glow }
    public var effect: Effect = .shadow
    /// Strength of the shadow or glow, 0...1. Zero turns it off.
    public var effectAmount: Double = 0.5
    /// The part of the recording that shows (S-025).
    public var crop: CropRect = .full

    /// The outline around the recording (S-026).
    public enum DeviceFrame: String, Codable, CaseIterable, Sendable { case none, border, browser, macBook }
    public var frame: DeviceFrame = .none
    /// Browser frame: show the address bar, and what it says.
    public var showsURLBar: Bool = true
    public var url: String = ""

    /// The canvas's shape (S-027). Auto follows the (cropped) recording.
    public enum Aspect: String, Codable, CaseIterable, Sendable {
        case auto, wide, tall, square, classic

        public var title: String {
            switch self {
            case .auto: "Auto"
            case .wide: "16:9"
            case .tall: "9:16"
            case .square: "1:1"
            case .classic: "4:3"
            }
        }

        /// Width over height, or nil for Auto.
        public var ratio: Double? {
            switch self {
            case .auto: nil
            case .wide: 16.0 / 9
            case .tall: 9.0 / 16
            case .square: 1
            case .classic: 4.0 / 3
            }
        }
    }
    public var aspect: Aspect = .auto

    // The camera in the editor (S-028): overrides on top of what was recorded.
    public enum CameraShape: String, Codable, CaseIterable, Sendable {
        case circle, roundedSquare
        /// Corner radius as a share of the bubble's size (matches the recorder's 24%).
        public var cornerRatio: Double { self == .circle ? 0.5 : 0.24 }
    }
    public struct Point: Codable, Equatable, Sendable {
        public var x: Double, y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }
    public var cameraVisible: Bool = true
    /// Size as a share of the recorded size, 0.5...2.
    public var cameraScale: Double = 1
    /// Nil keeps the shape picked while recording.
    public var cameraShape: CameraShape? = nil
    /// A white ring around the camera, 0...1.
    public var cameraBorder: Double = 0
    /// A shadow under the camera, 0...1.
    public var cameraShadow: Double = 0.4
    /// Set by dragging the camera on the canvas: its center for the whole
    /// video, normalized to the recording (top-left). Nil follows the recorded path.
    public var cameraPosition: Point? = nil

    /// How fast zooms ease in, out, and between spots (S-033).
    public var zoomSpeed: ZoomSpeed = .medium

    /// The drawn cursor (S-034): 1...3 times its size on the screen.
    public var cursorScale: Double = 1.5
    /// 0 draws the cursor where it was; 1 glides the most.
    public var cursorSmoothing: Double = 0.5
    /// Fades the cursor out when it has not moved for a while.
    public var cursorHidesWhenIdle: Bool = false

    /// A mark at each click (S-035): none, a filled ripple, or a ring.
    public enum ClickEffect: String, Codable, CaseIterable, Sendable { case none, ripple, ring }
    public var clickEffect: ClickEffect = .none
    public var clickColor: RGB = RGB(0.2, 0.5, 1)

    public init() {}

    /// The recording edge to edge, nothing around it: how M1 to M3 played.
    public static let plain: Style = {
        var style = Style()
        style.background = .none
        style.padding = 0
        style.rounding = 0
        style.effectAmount = 0
        style.cameraShadow = 0
        return style
    }()

    enum CodingKeys: String, CodingKey { case background, backgroundBlur, padding, rounding, effect, effectAmount, crop, frame, showsURLBar, url, aspect,
        cameraVisible, cameraScale, cameraShape, cameraBorder, cameraShadow, cameraPosition, zoomSpeed,
        cursorScale, cursorSmoothing, cursorHidesWhenIdle, clickEffect, clickColor }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Style()
        background = (try? c.decodeIfPresent(Background.self, forKey: .background)) ?? d.background
        backgroundBlur = (try? c.decodeIfPresent(Double.self, forKey: .backgroundBlur)) ?? d.backgroundBlur
        padding = (try? c.decodeIfPresent(Double.self, forKey: .padding)) ?? d.padding
        rounding = (try? c.decodeIfPresent(Double.self, forKey: .rounding)) ?? d.rounding
        effect = (try? c.decodeIfPresent(Effect.self, forKey: .effect)) ?? d.effect
        effectAmount = (try? c.decodeIfPresent(Double.self, forKey: .effectAmount)) ?? d.effectAmount
        crop = (try? c.decodeIfPresent(CropRect.self, forKey: .crop)) ?? d.crop
        frame = (try? c.decodeIfPresent(DeviceFrame.self, forKey: .frame)) ?? d.frame
        showsURLBar = (try? c.decodeIfPresent(Bool.self, forKey: .showsURLBar)) ?? d.showsURLBar
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? d.url
        aspect = (try? c.decodeIfPresent(Aspect.self, forKey: .aspect)) ?? d.aspect
        cameraVisible = (try? c.decodeIfPresent(Bool.self, forKey: .cameraVisible)) ?? d.cameraVisible
        cameraScale = (try? c.decodeIfPresent(Double.self, forKey: .cameraScale)) ?? d.cameraScale
        cameraShape = (try? c.decodeIfPresent(CameraShape.self, forKey: .cameraShape)) ?? d.cameraShape
        cameraBorder = (try? c.decodeIfPresent(Double.self, forKey: .cameraBorder)) ?? d.cameraBorder
        cameraShadow = (try? c.decodeIfPresent(Double.self, forKey: .cameraShadow)) ?? d.cameraShadow
        cameraPosition = (try? c.decodeIfPresent(Point.self, forKey: .cameraPosition)) ?? d.cameraPosition
        zoomSpeed = (try? c.decodeIfPresent(ZoomSpeed.self, forKey: .zoomSpeed)) ?? d.zoomSpeed
        cursorScale = (try? c.decodeIfPresent(Double.self, forKey: .cursorScale)) ?? d.cursorScale
        cursorSmoothing = (try? c.decodeIfPresent(Double.self, forKey: .cursorSmoothing)) ?? d.cursorSmoothing
        cursorHidesWhenIdle = (try? c.decodeIfPresent(Bool.self, forKey: .cursorHidesWhenIdle)) ?? d.cursorHidesWhenIdle
        clickEffect = (try? c.decodeIfPresent(ClickEffect.self, forKey: .clickEffect)) ?? d.clickEffect
        clickColor = (try? c.decodeIfPresent(RGB.self, forKey: .clickColor)) ?? d.clickColor
    }

    /// The style as a preset (S-029): without what belongs to one recording
    /// (its crop, the dragged camera position, the browser address).
    public var asPreset: Style {
        var preset = self
        preset.crop = .full
        preset.cameraPosition = nil
        preset.url = ""
        return preset
    }

    /// `preset` applied to this style: its look, with this recording's crop,
    /// camera position, and address kept.
    public func applying(preset: Style) -> Style {
        var style = preset
        style.crop = crop
        style.cameraPosition = cameraPosition
        style.url = url
        return style
    }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// The stored style, or the default one for a project that has none.
    public static func decode(_ data: Data?) -> Style {
        guard let data, let style = try? JSONDecoder().decode(Style.self, from: data) else { return Style() }
        return style
    }
}

/// Where the recording sits on the canvas.
public enum CanvasLayout {
    /// The output size for `style` from a recording of `source` pixels: the
    /// cropped recording's shape for Auto, otherwise the aspect's shape with
    /// the recording's long side kept. Even numbers, for the encoder.
    public static func canvasSize(for style: Style, source: CGSize) -> CGSize {
        let crop = style.crop.pixels(of: source).size
        let content = crop.width > 0 && crop.height > 0 ? crop : source
        func even(_ v: CGFloat) -> CGFloat { max(2, (v / 2).rounded() * 2) }
        guard let ratio = style.aspect.ratio else { return CGSize(width: even(content.width), height: even(content.height)) }
        let long = max(content.width, content.height)
        return ratio >= 1 ? CGSize(width: even(long), height: even(long / ratio))
                          : CGSize(width: even(long * ratio), height: even(long))
    }

    /// `rounding` (pixels at 1080p) in pixels of a canvas `height` tall.
    public static func cornerRadius(_ rounding: Double, canvasHeight height: CGFloat) -> CGFloat {
        CGFloat(min(max(rounding, 0), 40)) * height / 1080
    }

    /// The recording's rectangle: aspect-fit inside the canvas, inset on every
    /// side by `padding` times the canvas's shorter side. `chrome` is room the
    /// device frame needs around the recording; the recording and its frame
    /// fit inside the padding together.
    public static func screenRect(content: CGSize, canvas: CGSize, padding: Double,
                                  chrome: FrameInsets = .zero) -> CGRect {
        let inset = CGFloat(min(max(padding, 0), 0.3)) * min(canvas.width, canvas.height)
        let room = CGRect(origin: .zero, size: canvas).insetBy(dx: inset, dy: inset)
        let available = CGSize(width: room.width - chrome.left - chrome.right, height: room.height - chrome.top - chrome.bottom)
        guard content.width > 0, content.height > 0, available.width > 0, available.height > 0 else { return room }
        let scale = min(available.width / content.width, available.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        let outer = CGSize(width: size.width + chrome.left + chrome.right, height: size.height + chrome.top + chrome.bottom)
        return CGRect(x: room.midX - outer.width / 2 + chrome.left, y: room.midY - outer.height / 2 + chrome.top,
                      width: size.width, height: size.height)
    }

    /// Room a device frame takes around the recording, in pixels of a canvas
    /// `height` tall (sizes are set for 1080 and scale with the canvas).
    public static func chrome(for style: Style, canvasHeight height: CGFloat, contentWidth: CGFloat = 0) -> FrameInsets {
        let u = height / 1080
        switch style.frame {
        case .none: return .zero
        case .border: return FrameInsets(top: 10 * u, left: 10 * u, bottom: 10 * u, right: 10 * u)
        case .browser: return FrameInsets(top: (style.showsURLBar ? 52 : 36) * u, left: 0, bottom: 0, right: 0)
        // Bezel 18 on each side and 22 on top; the base is 22 tall and overhangs 42.
        case .macBook: return FrameInsets(top: 22 * u, left: 60 * u, bottom: 40 * u, right: 60 * u)
        }
    }
}

/// Space around the recording, in pixels, top-left origin.
public struct FrameInsets: Equatable, Sendable {
    public var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }

    public static let zero = FrameInsets(top: 0, left: 0, bottom: 0, right: 0)

    /// `rect` grown by these insets.
    public func outer(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX - left, y: rect.minY - top, width: rect.width + left + right, height: rect.height + top + bottom)
    }
}
