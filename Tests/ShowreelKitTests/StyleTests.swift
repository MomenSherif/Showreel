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

    @Test func paddingInsetsAndCenters() {
        let canvas = CGSize(width: 1000, height: 500)
        let rect = CanvasLayout.screenRect(content: CGSize(width: 1600, height: 1000), canvas: canvas, padding: 0.1)
        // 50 pt inset (10% of 500), then 16:10 fit into 900 × 400: 640 × 400.
        #expect(rect == CGRect(x: 180, y: 50, width: 640, height: 400))
        #expect(CanvasLayout.screenRect(content: canvas, canvas: canvas, padding: 0) == CGRect(origin: .zero, size: canvas))
    }
}
