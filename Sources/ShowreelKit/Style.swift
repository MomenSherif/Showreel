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

    public init() {}

    /// The recording edge to edge, nothing around it: how M1 to M3 played.
    public static let plain: Style = {
        var style = Style()
        style.background = .none
        style.padding = 0
        style.rounding = 0
        style.effectAmount = 0
        return style
    }()

    enum CodingKeys: String, CodingKey { case background, backgroundBlur, padding, rounding, effect, effectAmount, crop }

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
    /// `rounding` (pixels at 1080p) in pixels of a canvas `height` tall.
    public static func cornerRadius(_ rounding: Double, canvasHeight height: CGFloat) -> CGFloat {
        CGFloat(min(max(rounding, 0), 40)) * height / 1080
    }

    /// The recording's rectangle: aspect-fit inside the canvas, inset on every
    /// side by `padding` times the canvas's shorter side.
    public static func screenRect(content: CGSize, canvas: CGSize, padding: Double) -> CGRect {
        let inset = CGFloat(min(max(padding, 0), 0.3)) * min(canvas.width, canvas.height)
        let room = CGRect(origin: .zero, size: canvas).insetBy(dx: inset, dy: inset)
        guard content.width > 0, content.height > 0, room.width > 0, room.height > 0 else { return room }
        let scale = min(room.width / content.width, room.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: room.midX - size.width / 2, y: room.midY - size.height / 2, width: size.width, height: size.height)
    }
}
