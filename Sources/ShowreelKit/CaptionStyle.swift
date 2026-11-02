import Foundation

/// How captions look in the video (S-041, S-056). Part of `Style`, so presets
/// carry it. Every field decodes with a default, and styles saved before
/// S-056 (a `box` of none, dark, or light and a `highlightsWord` switch) load
/// as the same look.
public struct CaptionStyle: Codable, Equatable, Hashable, Sendable {
    public enum Position: String, Codable, CaseIterable, Sendable { case bottom, middle, top }

    /// The typeface. The four designs are the system's own, so they are on
    /// every Mac; a family is any installed font, and a missing one draws as System.
    public enum Font: Codable, Hashable, Sendable {
        case system, rounded, serif, mono
        case family(String)
    }

    public enum Weight: String, Codable, CaseIterable, Sendable { case regular, medium, semibold, bold, heavy, black }

    /// How the word being spoken stands out.
    public enum Highlight: String, Codable, CaseIterable, Sendable {
        case none
        /// A colored pill behind the word.
        case pill
        /// The word itself in the highlight color.
        case word
        /// Every word said so far in the highlight color.
        case karaoke
    }

    /// Light around the letters: a soft drop shadow, or a glow in the text color.
    public enum Shadow: String, Codable, CaseIterable, Sendable { case none, soft, glow }

    // Placement: picking a caption style keeps these.

    /// Captions show in the video.
    public var isVisible = true
    /// 0.6...1.6 times the standard size (46 px on a 1080-pixel canvas).
    public var size: Double = 1
    public var position: Position = .bottom

    // The look: what a caption style sets.

    public var font: Font = .system
    public var weight: Weight = .bold
    public var textColor = RGB(1, 1, 1)
    /// Every letter a capital.
    public var allCaps = false
    /// A rounded box behind the line.
    public var showsBox = true
    public var boxColor = RGB(0, 0, 0)
    /// 0...1.
    public var boxOpacity = 0.68
    /// The line around each letter, 0 (none) to 1 (thick).
    public var outline: Double = 0
    public var outlineColor = RGB(0, 0, 0)
    public var shadow: Shadow = .none
    public var highlight: Highlight = .pill
    public var highlightColor = RGB(hex: 0xFFD60A)

    public static let sizeRange: ClosedRange<Double> = 0.6...1.6

    public init() {}

    /// The word being spoken stands out.
    public var highlightsWord: Bool { highlight != .none }

    /// This placement with the look of `other`: what picking a caption style does.
    public func withLook(of other: CaptionStyle) -> CaptionStyle {
        var copy = other
        copy.isVisible = isVisible
        copy.size = size
        copy.position = position
        return copy
    }

    /// Same look as `other`, wherever and however big each one is.
    public func hasLook(of other: CaptionStyle) -> Bool { withLook(of: other) == self }

    enum CodingKeys: String, CodingKey {
        case isVisible, size, position, font, weight, textColor, allCaps, showsBox, boxColor, boxOpacity,
             outline, outlineColor, shadow, highlight, highlightColor
        // Before S-056.
        case box, highlightsWord
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = CaptionStyle()
        // A style from before S-056: its box sets the box, the text color,
        // and the shadow that used to show only without a box.
        switch try? c.decodeIfPresent(String.self, forKey: .box) {
        case "none": d.showsBox = false; d.shadow = .soft
        case "light": d.boxColor = RGB(1, 1, 1); d.boxOpacity = 0.92; d.textColor = RGB(0.08, 0.08, 0.1)
        default: break
        }
        if (try? c.decodeIfPresent(Bool.self, forKey: .highlightsWord)) == false { d.highlight = .none }

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        isVisible = value(.isVisible, d.isVisible)
        size = value(.size, d.size)
        position = value(.position, d.position)
        font = value(.font, d.font)
        weight = value(.weight, d.weight)
        textColor = value(.textColor, d.textColor)
        allCaps = value(.allCaps, d.allCaps)
        showsBox = value(.showsBox, d.showsBox)
        boxColor = value(.boxColor, d.boxColor)
        boxOpacity = value(.boxOpacity, d.boxOpacity)
        outline = value(.outline, d.outline)
        outlineColor = value(.outlineColor, d.outlineColor)
        shadow = value(.shadow, d.shadow)
        highlight = value(.highlight, d.highlight)
        highlightColor = value(.highlightColor, d.highlightColor)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(size, forKey: .size)
        try c.encode(position, forKey: .position)
        try c.encode(font, forKey: .font)
        try c.encode(weight, forKey: .weight)
        try c.encode(textColor, forKey: .textColor)
        try c.encode(allCaps, forKey: .allCaps)
        try c.encode(showsBox, forKey: .showsBox)
        try c.encode(boxColor, forKey: .boxColor)
        try c.encode(boxOpacity, forKey: .boxOpacity)
        try c.encode(outline, forKey: .outline)
        try c.encode(outlineColor, forKey: .outlineColor)
        try c.encode(shadow, forKey: .shadow)
        try c.encode(highlight, forKey: .highlight)
        try c.encode(highlightColor, forKey: .highlightColor)
    }
}

/// A caption style with a name: one of Showreel's (S-056) or one the person
/// saved (S-057).
public struct CaptionLook: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var style: CaptionStyle

    public init(id: String, name: String, style: CaptionStyle) {
        self.id = id
        self.name = name
        self.style = style
    }

    /// Showreel's caption styles, in the order of the inspector's tiles.
    /// Classic is the look captions had before S-056, and new projects get it.
    public static let all: [CaptionLook] = [
        CaptionLook(id: "classic", name: "Classic", style: CaptionStyle()),
        look("clean", "Clean") {
            $0.weight = .semibold; $0.showsBox = false; $0.shadow = .soft; $0.highlight = .word
        },
        look("bold-pop", "Bold Pop") {
            $0.weight = .black; $0.allCaps = true; $0.showsBox = false; $0.outline = 0.8; $0.shadow = .soft
            $0.highlight = .word; $0.highlightColor = RGB(hex: 0xFFE14D)
        },
        look("karaoke", "Karaoke") {
            $0.font = .rounded; $0.weight = .heavy; $0.showsBox = false; $0.outline = 0.45; $0.shadow = .soft
            $0.highlight = .karaoke; $0.highlightColor = RGB(hex: 0x5BE38A)
        },
        look("neon", "Neon") {
            $0.font = .rounded; $0.weight = .semibold; $0.textColor = RGB(hex: 0x8CF6FF); $0.showsBox = false
            $0.shadow = .glow; $0.highlight = .word; $0.highlightColor = RGB(hex: 0xFF6AD5)
        },
        look("paper", "Paper") {
            $0.font = .serif; $0.weight = .semibold; $0.textColor = RGB(hex: 0x1C1C1E)
            $0.boxColor = RGB(hex: 0xFFFDF7); $0.boxOpacity = 0.96; $0.highlightColor = RGB(hex: 0xFFD966)
        },
        look("terminal", "Terminal") {
            $0.font = .mono; $0.weight = .medium; $0.textColor = RGB(hex: 0x7CFF8F)
            $0.boxColor = RGB(hex: 0x0B0F0C); $0.boxOpacity = 0.88; $0.highlightColor = RGB(hex: 0x7CFF8F)
        },
        look("minimal", "Minimal") {
            $0.weight = .medium; $0.showsBox = false; $0.shadow = .soft; $0.highlight = .none
        },
    ]

    public static func named(_ id: String) -> CaptionLook? { all.first { $0.id == id } }

    private static func look(_ id: String, _ name: String, _ change: (inout CaptionStyle) -> Void) -> CaptionLook {
        var style = CaptionStyle()
        change(&style)
        return CaptionLook(id: id, name: name, style: style)
    }
}

/// The caption styles the person saved (S-057), kept as JSON in the app's
/// settings so every project can use them. Each has its own id.
public struct SavedCaptionLooks: Codable, Equatable, Sendable {
    public var looks: [CaptionLook]

    public init(looks: [CaptionLook] = []) { self.looks = looks }

    /// Adds the look of `style` as `name` (or "My Style" when blank), and
    /// returns it. The placement is not part of a saved style.
    public mutating func save(_ style: CaptionStyle, named name: String) -> CaptionLook {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let look = CaptionLook(id: UUID().uuidString, name: trimmed.isEmpty ? "My Style" : trimmed,
                               style: CaptionStyle().withLook(of: style))
        looks.append(look)
        return look
    }

    public mutating func delete(_ id: CaptionLook.ID) { looks.removeAll { $0.id == id } }

    public mutating func rename(_ id: CaptionLook.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = looks.firstIndex(where: { $0.id == id }) else { return }
        looks[i].name = trimmed
    }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    public static func decode(_ data: Data?) -> SavedCaptionLooks {
        guard let data, let looks = try? JSONDecoder().decode(SavedCaptionLooks.self, from: data) else { return SavedCaptionLooks() }
        return looks
    }

    /// The first of Showreel's styles, then the saved ones, with the look
    /// of `style`; nil when it is a look of its own ("Custom").
    public func match(_ style: CaptionStyle) -> CaptionLook? {
        (CaptionLook.all + looks).first { style.hasLook(of: $0.style) }
    }
}
