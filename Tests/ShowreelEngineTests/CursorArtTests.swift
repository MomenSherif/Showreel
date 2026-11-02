import CoreImage
import Testing
@testable import ShowreelEngine
import ShowreelKit

/// S-055: the cursors Showreel draws itself.
@Suite("Cursor styles")
struct CursorArtTests {
    @Test func everyStyleIsDrawnSharpWithItsClickPointInside() throws {
        #expect(Set(CursorArt.all.map(\.id)).count == CursorArt.all.count)
        for art in CursorArt.all {
            let sprite = try #require(art.sprite(), "\(art.id) did not draw")
            let extent = sprite.image.extent
            // 16 pixels a point: sharp at 3× on a zoomed 4K frame.
            #expect(extent.height >= 16 * sprite.pointHeight - 1, "\(art.id)")
            #expect(extent.contains(sprite.hotSpot), "\(art.id)")
        }
    }

    /// The tip of the drawing is on the click point, so clicks land where they did.
    @Test func clickPointIsOnTheDrawing() throws {
        for art in CursorArt.all {
            let image = try #require(art.image(pixelsPerPoint: 8))
            let alpha = Self.alpha(image, x: Int(art.hotSpot.x * 8), y: Int(art.hotSpot.y * 8), within: 12)
            #expect(alpha > 60, "\(art.id): nothing drawn at the click point")
        }
    }

    /// The largest alpha within `r` pixels of (x, y), from the top left.
    static func alpha(_ image: CGImage, x: Int, y: Int, within r: Int) -> Int {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var best = 0
        for yy in max(0, y - r)...min(h - 1, y + r) {
            for xx in max(0, x - r)...min(w - 1, x + r) { best = max(best, Int(bytes[(yy * w + xx) * 4 + 3])) }
        }
        return best
    }

    static func frame(with art: CursorArt, at point: (Double, Double)) throws -> Bitmap {
        var log = EventLog(source: CGRect(x: 0, y: 0, width: 160, height: 100))
        log.cursor = [EventLog.Point(t: 0, x: point.0, y: point.1)]
        let sprite = try #require(art.sprite())
        let cursor = CursorScene(track: CursorTrack(log: log, duration: 10, smoothing: 0),
                                 sprites: Dictionary(uniqueKeysWithValues: EventLog.Shape.Kind.allCases.map { ($0, sprite) }),
                                 pixelsPerPoint: 1, scale: 2)
        return Bitmap(Renderer.frame(screen: RendererTests.screen, camera: nil, at: 5, scene: RendererTests.scene,
                                     style: RenderStyle(style: .plain, cursor: cursor), size: RendererTests.size))
    }

    @Test func handAndWatermelonMatchGoldens() throws {
        try Self.frame(with: CursorArt.hand, at: (0.3, 0.3)).expectMatches(golden: "cursor-hand")
        try Self.frame(with: CursorArt.watermelon, at: (0.3, 0.3)).expectMatches(golden: "cursor-watermelon")
    }

    /// No cursor at all, while a click still gets its mark.
    @Test func noCursorKeepsTheClickMarks() {
        var log = EventLog(source: CGRect(x: 0, y: 0, width: 100, height: 100))
        log.cursor = [EventLog.Point(t: 0, x: 0.5, y: 0.5)]
        var style = Style.plain
        style.clickEffect = .ripple
        style.clickColor = RGB(1, 1, 1)
        func frame(at t: Double) -> Bitmap {
            let scene = CursorScene(track: CursorTrack(log: log, duration: 10, smoothing: 0), sprites: [:], pixelsPerPoint: 1,
                                    scale: 1, clicks: ClickMarks([EventLog.Click(t: 1, x: 0.5, y: 0.5, button: .left)]))
            return Bitmap(Renderer.frame(screen: RendererTests.screen, camera: nil, at: t, scene: RendererTests.scene,
                                         style: RenderStyle(style: style, cursor: scene), size: RendererTests.size))
        }
        let plain = Bitmap(Renderer.frame(screen: RendererTests.screen, camera: nil, at: 5, scene: RendererTests.scene,
                                          style: RenderStyle(style: .plain), size: RendererTests.size))
        #expect(frame(at: 5).bytes == plain.bytes, "no cursor is drawn")
        #expect(frame(at: 1.2).pixel(x: 160, y: 100).g > plain.pixel(x: 160, y: 100).g + 40, "the ripple shows")
    }
}
