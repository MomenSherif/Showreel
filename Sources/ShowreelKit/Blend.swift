import Foundation

/// A background Showreel draws itself (docs/GLOSSARY.md, "Blend"): soft
/// glows of color over a base, like light through frosted glass. Drawn at
/// the output size, so it is sharp at 4K and adds nothing to the app.
public struct BlendPreset: Equatable, Hashable, Sendable, Identifiable {
    /// One soft glow: a color fading out from a spot on the canvas.
    public struct Glow: Equatable, Hashable, Sendable {
        public let color: RGB
        /// The spot, normalized to the canvas, top-left origin.
        public let x: Double, y: Double
        /// How far it reaches, as a share of the canvas's longer side.
        public let radius: Double

        public init(_ hex: UInt32, x: Double, y: Double, radius: Double) {
            color = RGB(hex: hex)
            self.x = x
            self.y = y
            self.radius = radius
        }
    }

    public let id: String
    public let name: String
    public let base: RGB
    public let glows: [Glow]

    public init(id: String, name: String, base: UInt32, glows: [Glow]) {
        self.id = id
        self.name = name
        self.base = RGB(hex: base)
        self.glows = glows
    }

    /// The presets, in the order of the inspector's grid: darks first, then lights.
    public static let all: [BlendPreset] = [
        .init(id: "aurora", name: "Aurora", base: 0x0B1026, glows: [
            .init(0x2BD9A6, x: 0.18, y: 0.22, radius: 0.55), .init(0x6C4BF4, x: 0.82, y: 0.3, radius: 0.6),
            .init(0x1E90FF, x: 0.55, y: 0.95, radius: 0.5),
        ]),
        .init(id: "nebula", name: "Nebula", base: 0x1A0B2E, glows: [
            .init(0xFF4FA3, x: 0.22, y: 0.75, radius: 0.55), .init(0x7B2FF7, x: 0.75, y: 0.22, radius: 0.6),
            .init(0x00C2FF, x: 0.95, y: 0.9, radius: 0.42),
        ]),
        .init(id: "twilight", name: "Twilight", base: 0x120E2B, glows: [
            .init(0xFF7A59, x: 0.12, y: 0.9, radius: 0.55), .init(0x8B5CF6, x: 0.6, y: 0.3, radius: 0.6),
            .init(0xF59EBB, x: 0.95, y: 0.95, radius: 0.4),
        ]),
        .init(id: "grove", name: "Grove", base: 0x0F2A1D, glows: [
            .init(0xB6F36B, x: 0.22, y: 0.28, radius: 0.5), .init(0x2BC48A, x: 0.8, y: 0.72, radius: 0.6),
            .init(0xF5E663, x: 0.9, y: 0.1, radius: 0.32),
        ]),
        .init(id: "lava", name: "Lava", base: 0x1C0A06, glows: [
            .init(0xFF5A1F, x: 0.18, y: 0.85, radius: 0.55), .init(0xFFB224, x: 0.85, y: 0.22, radius: 0.45),
            .init(0xC2185B, x: 0.88, y: 0.95, radius: 0.45),
        ]),
        .init(id: "ink", name: "Ink", base: 0x101114, glows: [
            .init(0x3A4152, x: 0.22, y: 0.22, radius: 0.6), .init(0x2A2F3A, x: 0.8, y: 0.85, radius: 0.55),
            .init(0x5A6378, x: 0.88, y: 0.15, radius: 0.35),
        ]),
        .init(id: "sorbet", name: "Sorbet", base: 0xFFE3D3, glows: [
            .init(0xFF8FAB, x: 0.12, y: 0.18, radius: 0.55), .init(0xFFC46B, x: 0.88, y: 0.22, radius: 0.5),
            .init(0xB49CFF, x: 0.6, y: 0.95, radius: 0.6),
        ]),
        .init(id: "tide", name: "Tide", base: 0xE6F4FF, glows: [
            .init(0x6EC6FF, x: 0.18, y: 0.85, radius: 0.6), .init(0x3D7BFF, x: 0.85, y: 0.15, radius: 0.55),
            .init(0x8EF0D8, x: 0.8, y: 0.9, radius: 0.42),
        ]),
        .init(id: "bloom", name: "Bloom", base: 0xFFF1F5, glows: [
            .init(0xFF6FB5, x: 0.82, y: 0.78, radius: 0.55), .init(0xFFB86B, x: 0.18, y: 0.18, radius: 0.5),
            .init(0xC77DFF, x: 0.12, y: 0.9, radius: 0.45),
        ]),
        .init(id: "dune", name: "Dune", base: 0xF6E7D0, glows: [
            .init(0xE8A87C, x: 0.22, y: 0.8, radius: 0.6), .init(0xC38D9E, x: 0.85, y: 0.2, radius: 0.5),
            .init(0xF3D27A, x: 0.78, y: 0.9, radius: 0.45),
        ]),
        .init(id: "glacier", name: "Glacier", base: 0xF2F6FA, glows: [
            .init(0xB8D8F8, x: 0.18, y: 0.28, radius: 0.6), .init(0xD7C9F5, x: 0.82, y: 0.75, radius: 0.6),
            .init(0xC9F0EC, x: 0.72, y: 0.12, radius: 0.4),
        ]),
        .init(id: "lilac", name: "Lilac", base: 0xF4EEFF, glows: [
            .init(0xC4B5FD, x: 0.18, y: 0.2, radius: 0.6), .init(0xF9A8D4, x: 0.85, y: 0.8, radius: 0.5),
            .init(0x93C5FD, x: 0.9, y: 0.15, radius: 0.4),
        ]),
    ]

    public static func named(_ id: String) -> BlendPreset? { all.first { $0.id == id } }
}
