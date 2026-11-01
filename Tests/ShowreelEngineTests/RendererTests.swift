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
