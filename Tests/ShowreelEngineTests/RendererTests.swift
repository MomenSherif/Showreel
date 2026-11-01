import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShowreelEngine
import ShowreelKit

/// Golden-frame tests for the renderer (S-036). Sources are drawn in code, so
/// the frames are the same on every Mac. To accept a new look on purpose, run
/// `SHOWREEL_RECORD_GOLDEN=1 swift test ...` and look at the PNGs in Golden/.
@Suite("Renderer")
struct RendererTests {
    static let size = CGSize(width: 320, height: 200)

    /// A blue-to-violet screen at half the output size, so scaling is covered.
    static let screen: CIImage = {
        let rect = CGRect(x: 0, y: 0, width: 160, height: 100)
        return CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 160, y: 100),
            "inputColor0": CIColor(red: 0.2, green: 0.4, blue: 0.9),
            "inputColor1": CIColor(red: 0.5, green: 0.2, blue: 0.7),
        ])!.outputImage!.cropped(to: rect)
    }()

    /// A 16:9 camera: red on the left, green on the right, a white bar on top.
    /// The bubble mirrors it, so green must end up on the left.
    static let camera: CIImage = {
        let red = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.1)).cropped(to: CGRect(x: 0, y: 0, width: 80, height: 90))
        let green = CIImage(color: CIColor(red: 0.1, green: 0.8, blue: 0.2)).cropped(to: CGRect(x: 80, y: 0, width: 80, height: 90))
        let bar = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 70, width: 160, height: 20))
        return bar.composited(over: green.composited(over: red))
    }()

    static let scene = BubbleScene(bubble: [EventLog.Point(t: 0, x: 0.25, y: 0.3), EventLog.Point(t: 2, x: 0.75, y: 0.7)],
                                   fallbackCenter: CGPoint(x: 0.5, y: 0.5),
                                   hidden: [EventLog.Range(start: 3, end: 4)], diameter: 0.3)

    static func render(at t: Double, scene: BubbleScene = scene) -> Bitmap {
        Bitmap(Renderer.frame(screen: screen, camera: camera, at: t, scene: scene, size: size))
    }

    @Test func circleBubbleMatchesGolden() throws {
        try Self.render(at: 0).expectMatches(golden: "bubble-circle")
    }

    @Test func roundedSquareMatchesGolden() throws {
        var square = Self.scene
        square.cornerRatio = 0.22
        try Self.render(at: 2, scene: square).expectMatches(golden: "bubble-rounded-square")
    }

    @Test func hiddenCameraShowsOnlyTheScreen() throws {
        let hidden = Self.render(at: 3.5)
        let screenOnly = Bitmap(Renderer.frame(screen: Self.screen, camera: nil, at: 3.5, scene: Self.scene, size: Self.size))
        #expect(hidden.bytes == screenOnly.bytes)
        try hidden.expectMatches(golden: "screen-only")
    }

    // MARK: Style (S-022)

    static func styled(_ change: (inout Style) -> Void, image: CIImage? = nil) -> Bitmap {
        var style = Style()
        change(&style)
        return Bitmap(Renderer.frame(screen: screen, camera: camera, at: 0, scene: scene,
                                     style: RenderStyle(style: style, backgroundImage: image), size: size))
    }

    @Test func gradientWithPaddingMatchesGolden() throws {
        try Self.styled { $0.background = .gradient("sunrise"); $0.padding = 0.1 }.expectMatches(golden: "style-gradient")
    }

    /// S-023: corners are cut round; the background shows in them.
    @Test func roundingMatchesGolden() throws {
        let frame = Self.styled { $0.background = .color(RGB(1, 1, 1)); $0.padding = 0.1; $0.rounding = 40 }
        // 40 px at 1080p is 7.4 px here. The recording's corner pixel is background.
        let corner = frame.pixel(x: 20 + 1, y: 20 + 1)
        #expect(corner.r > 240 && corner.g > 240 && corner.b > 240, "the corner is cut, got \(corner)")
        try frame.expectMatches(golden: "style-rounding")
    }

    /// S-024: a shadow darkens the background below the recording; a glow lightens it.
    @Test func shadowAndGlowMatchGoldens() throws {
        let plain = Self.styled { $0.background = .color(RGB(0.5, 0.5, 0.5)); $0.padding = 0.2; $0.effectAmount = 0 }
        let shadow = Self.styled { $0.background = .color(RGB(0.5, 0.5, 0.5)); $0.padding = 0.2; $0.effect = .shadow; $0.effectAmount = 1 }
        let glow = Self.styled { $0.background = .color(RGB(0.5, 0.5, 0.5)); $0.padding = 0.2; $0.effect = .glow; $0.effectAmount = 1 }
        // Just below the recording's bottom edge, in the middle.
        let below = (x: 160, y: 200 - 40 + 6)
        #expect(shadow.pixel(x: below.x, y: below.y).r < plain.pixel(x: below.x, y: below.y).r - 10)
        #expect(glow.pixel(x: below.x, y: below.y).r > plain.pixel(x: below.x, y: below.y).r + 10)
        try shadow.expectMatches(golden: "style-shadow")
        try glow.expectMatches(golden: "style-glow")
    }

    /// S-025: a crop shows only part of the recording, scaled to fill the
    /// same space, and the bubble stays on its spot of the recording.
    @Test func cropMatchesGolden() throws {
        let frame = Self.styled { $0.background = .color(RGB(1, 1, 1)); $0.padding = 0.1; $0.effectAmount = 0
            $0.crop = CropRect(x: 0, y: 0, width: 0.5, height: 0.5) }
        // The top-left quarter holds the bubble (center 0.25, 0.3 → 0.5, 0.6 in the crop).
        let bubble = frame.pixel(x: 160 - 20, y: 20 + Int(0.6 * 160) + 10)
        #expect(bubble.g > 150, "the bubble is in the cropped frame, got \(bubble)")
        try frame.expectMatches(golden: "style-crop")
    }

    // MARK: Device frames (S-026)

    static func framed(_ frame: Style.DeviceFrame, size: CGSize = CGSize(width: 640, height: 400),
                       change: (inout Style) -> Void = { _ in }) -> Bitmap {
        var style = Style()
        style.background = .gradient("slate")
        style.padding = 0.1
        style.effectAmount = 0
        style.rounding = 20
        style.frame = frame
        change(&style)
        return Bitmap(Renderer.frame(screen: screen, camera: camera, at: 0, scene: scene,
                                     style: RenderStyle(style: style), size: size))
    }

    @Test func borderMatchesGolden() throws {
        try Self.framed(.border).expectMatches(golden: "frame-border")
    }

    @Test func browserMatchesGolden() throws {
        try Self.framed(.browser) { $0.url = "showreel.app" }.expectMatches(golden: "frame-browser")
    }

    @Test func browserWithoutURLBarIsShorter() {
        var style = Style()
        style.frame = .browser
        let withBar = CanvasLayout.chrome(for: style, canvasHeight: 1080).top
        style.showsURLBar = false
        #expect(CanvasLayout.chrome(for: style, canvasHeight: 1080).top < withBar)
    }

    @Test func macBookMatchesGolden() throws {
        try Self.framed(.macBook).expectMatches(golden: "frame-macbook")
    }

    /// Frames are drawn at the output size: at 4K the edge of a traffic light
    /// goes from page gray to red within two pixels.
    @Test func framesAreSharpAt4K() {
        let frame = Self.framed(.browser, size: CGSize(width: 3840, height: 2160))
        // The first light's center row; walk right from the window's left edge.
        let chrome = CanvasLayout.chrome(for: { var s = Style(); s.frame = .browser; return s }(), canvasHeight: 2160)
        let rect = CanvasLayout.screenRect(content: Self.screen.extent.size, canvas: CGSize(width: 3840, height: 2160),
                                           padding: 0.1, chrome: chrome)
        let u = 2.0, y = Int(rect.minY - chrome.top + 18 * u)
        var steepest = 0
        for x in Int(rect.minX)..<Int(rect.minX + 40 * u) {
            steepest = max(steepest, abs(frame.pixel(x: x + 1, y: y).g - frame.pixel(x: x, y: y).g))
        }
        #expect(steepest > 60, "a crisp edge changes fast, got \(steepest) per pixel")
    }

    /// S-027: on a 9:16 canvas the recording keeps its shape and its padding.
    @Test func tallCanvasMatchesGolden() throws {
        var style = Style()
        style.background = .gradient("lagoon")
        style.padding = 0.08
        style.aspect = .tall
        let size = CanvasLayout.canvasSize(for: style, source: CGSize(width: 320, height: 200))
        #expect(size == CGSize(width: 180, height: 320))
        let frame = Bitmap(Renderer.frame(screen: Self.screen, camera: Self.camera, at: 0, scene: Self.scene,
                                          style: RenderStyle(style: style), size: size))
        try frame.expectMatches(golden: "style-tall")
    }

    // MARK: Camera in the editor (S-028)

    /// A dragged position holds for the whole video: the bubble is in the
    /// same place before and after its recorded move at 2 s.
    @Test func draggedCameraStaysPutForTheWholeVideo() {
        func frame(at t: Double) -> Bitmap {
            var style = Style.plain
            style.cameraPosition = Style.Point(x: 0.8, y: 0.25)
            return Bitmap(Renderer.frame(screen: Self.screen, camera: Self.camera, at: t, scene: Self.scene,
                                         style: RenderStyle(style: style), size: Self.size))
        }
        // (0.8, 0.25) of 320 × 200: x 256, y 50. Left half of the bubble is green.
        for t in [0.0, 2.5] {
            let p = frame(at: t).pixel(x: 256 - 25, y: 50 + 10)
            #expect(p.g > 150, "at \(t) s the camera is where it was dragged, got \(p)")
        }
    }

    @Test func hiddenCameraIsNotDrawn() {
        var style = Style.plain
        style.cameraVisible = false
        let frame = Bitmap(Renderer.frame(screen: Self.screen, camera: Self.camera, at: 0, scene: Self.scene,
                                          style: RenderStyle(style: style), size: Self.size))
        let screenOnly = Bitmap(Renderer.frame(screen: Self.screen, camera: nil, at: 0, scene: Self.scene, size: Self.size))
        #expect(frame.bytes == screenOnly.bytes)
    }

    @Test func cameraStyleMatchesGolden() throws {
        try Self.styled {
            $0.background = .color(RGB(0.9, 0.9, 0.92)); $0.padding = 0.1; $0.effectAmount = 0
            $0.cameraScale = 1.5; $0.cameraShape = .roundedSquare; $0.cameraBorder = 1; $0.cameraShadow = 1
            $0.cameraPosition = Style.Point(x: 0.75, y: 0.65)
        }.expectMatches(golden: "camera-style")
    }

    @Test func solidColorShowsAroundTheRecording() {
        let frame = Self.styled { $0.background = .color(RGB(1, 0, 0)); $0.padding = 0.1 }
        let corner = frame.pixel(x: 4, y: 4)
        #expect(corner.r > 250 && corner.g < 5 && corner.b < 5, "the padding shows the color, got \(corner)")
        let middle = frame.pixel(x: 200, y: 150)
        #expect(middle.b > middle.r, "the recording sits in the middle, got \(middle)")
    }

    @Test func blurredImageMatchesGolden() throws {
        // A hard-edged picture: blur must soften its edge.
        let left = CIImage(color: CIColor(red: 1, green: 0.8, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 60))
        let right = CIImage(color: CIColor(red: 0, green: 0.3, blue: 0.6)).cropped(to: CGRect(x: 50, y: 0, width: 50, height: 60))
        let picture = right.composited(over: left)
        let sharp = Self.styled({ $0.background = .image("bg.png"); $0.padding = 0.2 }, image: picture)
        let blurred = Self.styled({ $0.background = .image("bg.png"); $0.padding = 0.2; $0.backgroundBlur = 0.5 }, image: picture)
        #expect(sharp.bytes != blurred.bytes)
        try blurred.expectMatches(golden: "style-image-blur")
    }

    @Test func missingPictureFallsBackToAGradient() {
        let frame = Self.styled { $0.background = .wallpaper("/nowhere.heic"); $0.padding = 0.2 }
        let corner = frame.pixel(x: 2, y: 2)
        #expect(corner.r + corner.g + corner.b > 100, "not black, got \(corner)")
    }

    @Test func frameFillsTheOutputSize() {
        let image = Renderer.frame(screen: Self.screen, camera: Self.camera, at: 0, scene: Self.scene, size: Self.size)
        #expect(image.extent == CGRect(origin: .zero, size: Self.size))
    }

    @Test func bubbleIsMirroredAndPlacedFromTheTopLeft() {
        let frame = Self.render(at: 0)
        // Center (0.25, 0.3) from the top-left: x 80, y 60 rows down. Diameter 96.
        let left = frame.pixel(x: 80 - 30, y: 60 + 10), right = frame.pixel(x: 80 + 30, y: 60 + 10)
        #expect(left.g > 150 && left.r < 80, "mirrored: green on the left, got \(left)")
        #expect(right.r > 180 && right.g < 80, "mirrored: red on the right, got \(right)")
        let top = frame.pixel(x: 80, y: 60 - 40)
        #expect(top.r > 220 && top.g > 220 && top.b > 220, "the camera's top stays on top, got \(top)")
        let outside = frame.pixel(x: 80, y: 60 + 60)
        #expect(outside.b > outside.r, "outside the circle is the screen, got \(outside)")
    }

    @Test func bubbleFollowsItsNewestLoggedPosition() {
        // From t 2 the center is (0.75, 0.7): x 240, y 140 rows down.
        let frame = Self.render(at: 2.5)
        let moved = frame.pixel(x: 240 - 30, y: 140 + 10)
        #expect(moved.g > 150, "the bubble moved at t 2, got \(moved)")
        let old = frame.pixel(x: 80 - 30, y: 60 + 10)
        #expect(old.b > old.g, "the old spot shows the screen again, got \(old)")
    }
}

/// An RGBA8 sRGB bitmap, top row first.
struct Bitmap {
    let width: Int, height: Int
    var bytes: [UInt8]

    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    init(_ image: CIImage) {
        width = Int(image.extent.width); height = Int(image.extent.height)
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        Self.context.render(image, toBitmap: &bytes, rowBytes: width * 4, bounds: image.extent, format: .RGBA8, colorSpace: Self.space)
    }

    init?(png url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        width = image.width; height = image.height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: Self.space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !ok { return nil }
    }

    func pixel(x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    func writePNG(to url: URL) throws {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: Self.space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Passes when no channel is more than 2 levels off and the mean error is
    /// under 0.5 levels: GPU rounding passes, a moved or recolored bubble fails.
    func expectMatches(golden name: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Golden").appendingPathComponent("\(name).png")
        if ProcessInfo.processInfo.environment["SHOWREEL_RECORD_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writePNG(to: url)
            return
        }
        let golden = try #require(Bitmap(png: url), "missing golden \(name).png: record it", sourceLocation: sourceLocation)
        try #require(golden.width == width && golden.height == height, "size changed", sourceLocation: sourceLocation)
        var worst = 0, total = 0
        for (a, b) in zip(bytes, golden.bytes) {
            let d = abs(Int(a) - Int(b))
            worst = max(worst, d); total += d
        }
        let mean = Double(total) / Double(bytes.count)
        if worst > 2 || mean > 0.5 {
            let failed = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-actual.png")
            try? writePNG(to: failed)
            Issue.record("\(name) differs from its golden: worst \(worst), mean \(mean). Actual: \(failed.path)",
                         sourceLocation: sourceLocation)
        }
    }
}
