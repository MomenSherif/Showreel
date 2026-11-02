import CoreImage
import Testing
@testable import ShowreelEngine
import ShowreelKit

/// S-048: a blur hides part of the recording itself, so it stays on the
/// same content through crops and zooms, and only that part changes.
@Suite("Blur rendering")
struct BlurRenderTests {
    static let size = CGSize(width: 320, height: 200)

    /// Black and white squares, 10 px, so a blur shows as gray.
    static let screen: CIImage = {
        CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputCenter": CIVector(x: 0, y: 0), "inputColor0": CIColor.white, "inputColor1": CIColor.black,
            "inputWidth": 10, "inputSharpness": 1,
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 160, height: 100))
    }()

    static let scene = BubbleScene(bubble: [], fallbackCenter: CGPoint(x: 0.5, y: 0.5), hidden: [], diameter: 0.3)
    /// The lower-right part of the recording, from 2 to 4 seconds.
    static let blur = BlurRegion(start: 2, end: 4, rect: CropRect(x: 0.5, y: 0.5, width: 0.25, height: 0.3), strength: 1)

    static func frame(at t: Double = 3, blur: BlurRegion? = blur, crop: CropRect = .full, zooms: ZoomTrack = ZoomTrack()) -> Bitmap {
        var style = Style.plain
        style.crop = crop
        let blurs = BlurTrack(regions: blur.map { [$0] } ?? [])
        return Bitmap(Renderer.frame(screen: screen, camera: nil, at: t, scene: scene,
                                     style: RenderStyle(style: style, zooms: zooms, blurs: blurs), size: size))
    }

    /// How far a pixel is from black or white: 0 on the checkerboard, 127 for mid gray.
    static func grayness(_ p: (r: Int, g: Int, b: Int)) -> Int { min(p.r, 255 - p.r) }

    @Test func onlyTheAreaIsBlurred() throws {
        let plain = Self.frame(blur: nil), blurred = Self.frame()
        // The area is x 160..<240, y 100..<160 of the output (2× the recording).
        var inside = 0, outsideDiff = 0
        for y in 0..<200 { for x in 0..<320 {
            let a = plain.pixel(x: x, y: y), b = blurred.pixel(x: x, y: y)
            if (162..<238).contains(x) && (102..<158).contains(y) {
                inside = max(inside, Self.grayness(b))
            } else if !(158..<242).contains(x) || !(98..<162).contains(y) {
                outsideDiff = max(outsideDiff, abs(a.r - b.r))
            }
        } }
        #expect(Self.grayness(blurred.pixel(x: 200, y: 130)) > 60, "the middle of the area is gray")
        #expect(inside > 60)
        #expect(outsideDiff == 0, "outside the area nothing changes, got \(outsideDiff)")
        try blurred.expectMatches(golden: "blur")
    }

    @Test func onlyWhileItRuns() {
        #expect(Self.frame(at: 1).bytes == Self.frame(at: 1, blur: nil).bytes)
        #expect(Self.frame(at: 4.5).bytes == Self.frame(at: 4.5, blur: nil).bytes)
    }

    /// A crop of the lower-right quarter makes the area fill the top-left of the frame.
    @Test func staysOnTheContentThroughACrop() {
        let frame = Self.frame(crop: CropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        // Recording (0.5...0.75, 0.5...0.8) → crop (0...0.5, 0...0.6) → output x 0..<160, y 0..<120.
        #expect(Self.grayness(frame.pixel(x: 80, y: 60)) > 60, "blurred where the area moved to")
        #expect(Self.grayness(frame.pixel(x: 250, y: 170)) == 0, "the rest of the crop is sharp")
    }

    /// A 2× zoom on the same quarter shows the same pixels as the crop.
    @Test func staysOnTheContentThroughAZoom() {
        let zooms = ZoomTrack(segments: [ZoomSegment(start: 0, end: 10, scale: 2, x: 0.75, y: 0.75)])
        let zoomed = Self.frame(zooms: zooms), cropped = Self.frame(crop: CropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        #expect(Self.grayness(zoomed.pixel(x: 80, y: 60)) > 60)
        var maxDiff = 0
        for y in stride(from: 4, to: 196, by: 3) { for x in stride(from: 4, to: 316, by: 3) {
            maxDiff = max(maxDiff, abs(zoomed.pixel(x: x, y: y).r - cropped.pixel(x: x, y: y).r))
        } }
        #expect(maxDiff <= 3, "zoom and crop differ by \(maxDiff)")
    }

    @Test func pixelateMatchesGolden() throws {
        var blur = Self.blur
        blur.style = .pixelate
        let frame = Self.frame(blur: blur)
        #expect(frame.bytes != Self.frame(blur: nil).bytes)
        try frame.expectMatches(golden: "pixelate")
    }
}
