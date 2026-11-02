import CoreGraphics
import Foundation
import Testing
@testable import ShowreelKit

@Suite("Style")
struct StyleTests {
    @Test func atLeastTwelveGradients() {
        #expect(GradientPreset.all.count >= 12)
        #expect(Set(GradientPreset.all.map(\.id)).count == GradientPreset.all.count)
    }

    @Test func savesAndLoads() {
        var style = Style()
        style.background = .color(RGB(0.1, 0.2, 0.3))
        style.backgroundBlur = 0.4
        #expect(Style.decode(style.encoded()) == style)
        #expect(Style.decode(nil) == Style())
    }

    /// S-055: the cursor look is saved, and older styles show the system cursor.
    @Test func cursorLookSavesAndLoads() {
        for look: Style.CursorLook in [.system, .none, .art("hand"), .picture("cursor-1.png", centered: true)] {
            var style = Style()
            style.cursorLook = look
            #expect(Style.decode(style.encoded()).cursorLook == look)
        }
        #expect(Style.decode(Data(#"{"padding":0.2}"#.utf8)).cursorLook == .system)
    }

    /// A style saved before a field existed still loads, with that field's default.
    @Test func missingFieldsGetDefaults() {
        let old = Data(#"{"padding":0.2}"#.utf8)
        let style = Style.decode(old)
        #expect(style.padding == 0.2)
        #expect(style.background == Style().background)
    }

    @Test func roundingScalesWithTheCanvas() {
        #expect(CanvasLayout.cornerRadius(20, canvasHeight: 1080) == 20)
        #expect(CanvasLayout.cornerRadius(20, canvasHeight: 2160) == 40)
        #expect(CanvasLayout.cornerRadius(90, canvasHeight: 1080) == 40)
    }

    /// S-026: the recording and its frame fit inside the padding together.
    @Test func frameChromeFitsInsideThePadding() {
        var style = Style()
        style.frame = .browser
        let canvas = CGSize(width: 1920, height: 1080)
        let chrome = CanvasLayout.chrome(for: style, canvasHeight: canvas.height)
        #expect(chrome.top == 52)
        let rect = CanvasLayout.screenRect(content: CGSize(width: 1600, height: 1000), canvas: canvas, padding: 0.1, chrome: chrome)
        let outer = chrome.outer(rect)
        let room = CGRect(origin: .zero, size: canvas).insetBy(dx: 108, dy: 108)
        #expect(room.insetBy(dx: -0.5, dy: -0.5).contains(outer))
        #expect(abs(outer.midY - room.midY) < 0.5 && abs(outer.midX - room.midX) < 0.5)
        #expect(abs(rect.width / rect.height - 1.6) < 0.001)
    }

    /// S-027: the canvas takes the aspect's shape and keeps the long side.
    @Test func aspectSetsTheCanvas() {
        var style = Style()
        let source = CGSize(width: 1600, height: 1000)
        #expect(CanvasLayout.canvasSize(for: style, source: source) == source)
        style.aspect = .wide
        #expect(CanvasLayout.canvasSize(for: style, source: source) == CGSize(width: 1600, height: 900))
        style.aspect = .tall
        #expect(CanvasLayout.canvasSize(for: style, source: source) == CGSize(width: 900, height: 1600))
        style.aspect = .square
        #expect(CanvasLayout.canvasSize(for: style, source: source) == CGSize(width: 1600, height: 1600))
        style.aspect = .auto
        style.crop = CropRect(x: 0, y: 0, width: 0.5, height: 0.5)
        #expect(CanvasLayout.canvasSize(for: style, source: source) == CGSize(width: 800, height: 500))
    }

    /// S-029: a preset carries the look, not one recording's crop or camera spot.
    @Test func presetsKeepTheRecordingsOwnValues() {
        var mine = Style()
        mine.crop = CropRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        mine.cameraPosition = Style.Point(x: 0.2, y: 0.3)
        mine.url = "mine.app"
        var other = Style()
        other.background = .gradient("ember")
        other.padding = 0.2
        other.frame = .macBook
        other.crop = CropRect(x: 0, y: 0, width: 0.9, height: 0.9)
        let preset = other.asPreset
        #expect(preset.crop.isFull && preset.cameraPosition == nil)
        let applied = mine.applying(preset: preset)
        #expect(applied.background == .gradient("ember") && applied.padding == 0.2 && applied.frame == .macBook)
        #expect(applied.crop == mine.crop && applied.cameraPosition == mine.cameraPosition && applied.url == "mine.app")
    }

    @Test func paddingInsetsAndCenters() {
        let canvas = CGSize(width: 1000, height: 500)
        let rect = CanvasLayout.screenRect(content: CGSize(width: 1600, height: 1000), canvas: canvas, padding: 0.1)
        // 50 pt inset (10% of 500), then 16:10 fit into 900 × 400: 640 × 400.
        #expect(rect == CGRect(x: 180, y: 50, width: 640, height: 400))
        #expect(CanvasLayout.screenRect(content: canvas, canvas: canvas, padding: 0) == CGRect(origin: .zero, size: canvas))
    }
}
