import CoreImage
import Testing
@testable import ShowreelEngine
import ShowreelKit

/// Blends (docs/GLOSSARY.md): soft glows drawn at the output size.
@Suite("Blend backgrounds")
struct BlendTests {
    static func frame(_ id: String, size: CGSize = CGSize(width: 320, height: 200)) -> Bitmap {
        var style = Style()
        style.background = .blend(id)
        return Bitmap(Renderer.frame(screen: RendererTests.screen, camera: nil, at: 0, scene: RendererTests.scene,
                                     style: RenderStyle(style: style), size: size))
    }

    @Test func auroraMatchesGolden() throws {
        try Self.frame("aurora").expectMatches(golden: "blend-aurora")
    }

    @Test func sorbetMatchesGolden() throws {
        try Self.frame("sorbet").expectMatches(golden: "blend-sorbet")
    }

    /// Every preset draws, with its glows: the corners are not all the base color.
    @Test func everyPresetShowsItsGlows() {
        for preset in BlendPreset.all {
            let frame = Self.frame(preset.id)
            let corners = [frame.pixel(x: 2, y: 2), frame.pixel(x: 317, y: 2), frame.pixel(x: 2, y: 197), frame.pixel(x: 317, y: 197)]
            let spread = corners.map { $0.r + $0.g + $0.b }
            #expect((spread.max() ?? 0) - (spread.min() ?? 0) > 30, "\(preset.name): \(corners)")
        }
    }

    /// No bands: neighboring pixels along a row differ by a few levels at most.
    @Test func glowsFadeSmoothly() {
        let frame = Self.frame("nebula", size: CGSize(width: 640, height: 400))
        var worst = 0
        for x in 1..<640 {
            let a = frame.pixel(x: x - 1, y: 8), b = frame.pixel(x: x, y: 8)
            worst = max(worst, abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
        }
        #expect(worst <= 3, "a step of \(worst) levels")
    }

    /// An unknown id (a newer version's preset) draws the first blend.
    @Test func unknownBlendFallsBack() {
        #expect(Self.frame("not-a-blend").bytes == Self.frame(BlendPreset.all[0].id).bytes)
    }
}
