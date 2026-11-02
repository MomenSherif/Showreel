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

    // MARK: Zoom (S-030)

    /// A 2× zoom on the top-left quarter shows the same pixels as a crop of
    /// it, in the same place; unlike a crop, the camera stays where it was.
    @Test func zoomShowsPartOfTheRecordingInTheSamePlace() throws {
        let zooms = ZoomTrack(segments: [ZoomSegment(start: 0, end: 10, scale: 2, x: 0.25, y: 0.25)])
        func frame(_ style: Style, zooms: ZoomTrack = ZoomTrack(), camera: CIImage? = nil) -> Bitmap {
            Bitmap(Renderer.frame(screen: Self.screen, camera: camera, at: 5, scene: Self.scene,
                                  style: RenderStyle(style: style, zooms: zooms), size: Self.size))
        }
        var plain = Style()
        plain.background = .color(RGB(1, 1, 1)); plain.padding = 0.1; plain.effectAmount = 0; plain.rounding = 0
        var crop = plain
        crop.crop = CropRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let zoomed = frame(plain, zooms: zooms), cropped = frame(crop)
        // Inside the screen (256 × 160 at 32, 20); a crop's scaled edge is
        // soft, so the outer 3 pixels are left out.
        var maxDiff = 0
        for y in 23..<177 { for x in 35..<285 {
            let a = zoomed.pixel(x: x, y: y), b = cropped.pixel(x: x, y: y)
            maxDiff = max(maxDiff, abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
        } }
        #expect(maxDiff <= 3, "zoom and crop differ by \(maxDiff)")
        // Before and after the zoom, the whole recording shows.
        #expect(frame(plain, zooms: ZoomTrack(segments: [ZoomSegment(start: 6, end: 9)])).bytes == frame(plain).bytes)
        // The camera keeps its spot on the canvas.
        let withCamera = frame(plain, zooms: zooms, camera: Self.camera)
        // At t = 5 the scene puts the bubble at (0.75, 0.7) of the 256 × 160 screen at (32, 20).
        let bubble = withCamera.pixel(x: 32 + Int(0.75 * 256), y: 20 + Int(0.7 * 160) + 5)
        #expect(bubble.g > 150 || bubble.r > 150, "the bubble did not move, got \(bubble)")
        try withCamera.expectMatches(golden: "zoom-2x")
    }

    // MARK: Cursor (S-034)

    /// A cursor picture: red, 10 by 16 points drawn at 10× (100 × 160
    /// pixels), its click point at the top-left corner.
    static let sprite = CursorSprite(image: CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 160)),
                                     hotSpot: .zero, pointHeight: 16)

    static func withCursor(at point: (Double, Double), zooms: ZoomTrack = ZoomTrack(), scale: Double = 1,
                           screen: CIImage = screen, size: CGSize = size, pixelsPerPoint: CGFloat = 1) -> Bitmap {
        var log = EventLog(source: CGRect(x: 0, y: 0, width: 100, height: 100))
        log.cursor = [EventLog.Point(t: 0, x: point.0, y: point.1)]
        let cursor = CursorScene(track: CursorTrack(log: log, duration: 10, smoothing: 0), sprites: [.arrow: sprite],
                                 pixelsPerPoint: pixelsPerPoint, scale: scale)
        return Bitmap(Renderer.frame(screen: screen, camera: nil, at: 5, scene: scene,
                                     style: RenderStyle(style: .plain, zooms: zooms, cursor: cursor), size: size))
    }

    /// S-034: the cursor is drawn from the log, its click point on the spot,
    /// at its size on screen times the recording's scale on the canvas.
    @Test func cursorIsDrawnAtItsSpotAndSize() throws {
        // The 160 × 100 screen fills 320 × 200: 2 output pixels per recorded pixel,
        // so the cursor is 32 pixels tall and 20 wide, its corner at (160, 100).
        let frame = Self.withCursor(at: (0.5, 0.5))
        #expect(frame.pixel(x: 162, y: 102).r > 240 && frame.pixel(x: 162, y: 102).g < 15)
        #expect(frame.pixel(x: 178, y: 130).r > 240)
        #expect(frame.pixel(x: 158, y: 110).r < 200, "nothing left of the click point")
        #expect(frame.pixel(x: 170, y: 134).r < 200, "32 pixels tall")
        try frame.expectMatches(golden: "cursor")
        // A 2× zoom on the spot doubles it.
        let zoomed = Self.withCursor(at: (0.5, 0.5), zooms: ZoomTrack(segments: [ZoomSegment(start: 0, end: 10, x: 0.5, y: 0.5)]))
        #expect(zoomed.pixel(x: 170, y: 160).r > 240 && zoomed.pixel(x: 170, y: 166).r < 200)
        // Size 2× doubles it too.
        #expect(Self.withCursor(at: (0.5, 0.5), scale: 2).pixel(x: 195, y: 160).r > 240)
    }

    /// S-034: a big cursor stays sharp on a 4K video.
    @Test func largeCursorIsCrispAt4K() {
        let screen = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let frame = Self.withCursor(at: (0.5, 0.5), scale: 3, screen: screen, size: CGSize(width: 3840, height: 2160), pixelsPerPoint: 2)
        // 16 pt × 2 px/pt × 2 (to 4K) × 3 = 192 px tall, 120 wide, its corner at (1920, 1080).
        #expect(frame.pixel(x: 1925, y: 1265).r > 240 && frame.pixel(x: 1925, y: 1275).r < 15)
        // Across the cursor's left edge, at most 2 pixels are in between red and blue.
        let row = (1915...1925).map { frame.pixel(x: $0, y: 1150).r }
        #expect(row.filter { $0 > 15 && $0 < 240 }.count <= 2, "\(row)")
    }

    /// S-035: a ripple shows at a click for 400 ms, then is gone.
    @Test func clickRippleShowsFor400Milliseconds() throws {
        var log = EventLog(source: CGRect(x: 0, y: 0, width: 100, height: 100))
        log.cursor = [EventLog.Point(t: 0, x: 0.9, y: 0.9)]
        let click = EventLog.Click(t: 1, x: 0.25, y: 0.5, button: .left)
        func frame(at t: Double, _ effect: Style.ClickEffect) -> Bitmap {
            var style = Style.plain
            style.clickEffect = effect
            style.clickColor = RGB(1, 1, 1)
            let cursor = CursorScene(track: CursorTrack(log: log, duration: 10, smoothing: 0), sprites: [:],
                                     pixelsPerPoint: 1, scale: 1, clicks: ClickMarks([click]))
            return Bitmap(Renderer.frame(screen: Self.screen, camera: nil, at: t, scene: Self.scene,
                                         style: RenderStyle(style: style, cursor: cursor), size: Self.size))
        }
        // The click is at (80, 100) on the 320 × 200 canvas.
        let plain = frame(at: 1.2, .none).pixel(x: 80, y: 100)
        let ripple = frame(at: 1.2, .ripple)
        #expect(ripple.pixel(x: 80, y: 100).g > plain.g + 40, "lighter at the click")
        #expect(frame(at: 1.41, .ripple).pixel(x: 80, y: 100) == plain, "gone after 400 ms")
        #expect(frame(at: 0.9, .ripple).pixel(x: 80, y: 100) == plain, "not before the click")
        // A ring leaves its middle clear once it has grown.
        let ring = frame(at: 1.2, .ring)
        #expect(ring.pixel(x: 80, y: 100) == plain)
        try ripple.expectMatches(golden: "click-ripple")
        try ring.expectMatches(golden: "click-ring")
    }

    @Test func noCursorSceneDrawsNoCursor() {
        let plain = Bitmap(Renderer.frame(screen: Self.screen, camera: nil, at: 5, scene: Self.scene,
                                          style: RenderStyle(style: .plain), size: Self.size))
        #expect(plain.pixel(x: 165, y: 105).r < 200)
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

    // MARK: Captions (S-041)

    static let captions = CaptionTrack(captions: [
        Caption(words: ["Click", "Create", "Workspace", "to", "start."].enumerated().map { i, w in
            CaptionWord(text: w, start: 1 + Double(i) * 0.4, end: 1.35 + Double(i) * 0.4)
        }),
    ])

    static func captioned(at t: Double, size: CGSize = CGSize(width: 640, height: 400), _ change: (inout CaptionStyle) -> Void = { _ in }) -> Bitmap {
        var style = Style()
        style.background = .gradient("graphite")
        change(&style.captions)
        return Bitmap(Renderer.frame(screen: screen, camera: nil, at: t, scene: scene,
                                     style: RenderStyle(style: style, captions: captions), size: size))
    }

    @Test func captionWithSpokenWordMatchesGolden() throws {
        // 1.85 s: the third word, "Workspace", is being spoken.
        try Self.captioned(at: 1.85).expectMatches(golden: "captions-dark-bottom")
    }

    @Test func lightBoxAtTheTopMatchesGolden() throws {
        try Self.captioned(at: 2.7) {
            $0.boxColor = RGB(1, 1, 1); $0.boxOpacity = 0.92; $0.textColor = RGB(0.08, 0.08, 0.1)
            $0.position = .top; $0.size = 1.4
        }
            .expectMatches(golden: "captions-light-top")
    }

    @Test func captionsShowOnlyWhileTheirCaptionLasts() {
        let none = Self.captioned(at: 0.5)
        let after = Self.captioned(at: 4)
        let hidden = Self.captioned(at: 1.85) { $0.isVisible = false }
        #expect(none.bytes == after.bytes)
        #expect(hidden.bytes == none.bytes)
        #expect(Self.captioned(at: 1.85).bytes != none.bytes)
    }

    @Test func highlightMovesWithTheSpokenWord() {
        let second = Self.captioned(at: 1.85), third = Self.captioned(at: 2.25)
        #expect(second.bytes != third.bytes)
        let plain = Self.captioned(at: 1.85) { $0.highlight = .none }
        #expect(plain.bytes == Self.captioned(at: 2.25) { $0.highlight = .none }.bytes)
    }

    // MARK: Caption styles (S-056)

    @Test func everyCaptionStyleDrawsDifferently() {
        let frames = CaptionLook.all.map { look in Self.captioned(at: 1.85) { $0 = $0.withLook(of: look.style) } }
        for (i, a) in frames.enumerated() {
            for (j, b) in frames.enumerated() where j > i {
                #expect(a.bytes != b.bytes, "\(CaptionLook.all[i].name) and \(CaptionLook.all[j].name) look the same")
            }
        }
    }

    @Test func boldPopMatchesGolden() throws {
        try Self.captioned(at: 1.85) { $0 = $0.withLook(of: CaptionLook.named("bold-pop")!.style) }
            .expectMatches(golden: "captions-bold-pop")
    }

    @Test func neonMatchesGolden() throws {
        try Self.captioned(at: 2.25) { $0 = $0.withLook(of: CaptionLook.named("neon")!.style); $0.position = .middle }
            .expectMatches(golden: "captions-neon-middle")
    }

    @Test func eachCaptionSettingChangesTheFrame() {
        let base = Self.captioned(at: 1.85)
        let changes: [(String, (inout CaptionStyle) -> Void)] = [
            ("font", { $0.font = .serif }), ("weight", { $0.weight = .regular }), ("text color", { $0.textColor = RGB(1, 0, 0) }),
            ("all caps", { $0.allCaps = true }), ("box", { $0.showsBox = false }), ("box color", { $0.boxColor = RGB(0, 0, 1) }),
            ("box opacity", { $0.boxOpacity = 0.3 }), ("outline", { $0.outline = 0.5 }), ("shadow", { $0.shadow = .glow }),
            ("highlight", { $0.highlight = .karaoke }), ("position", { $0.position = .middle }),
        ]
        for (name, change) in changes { #expect(Self.captioned(at: 1.85, change).bytes != base.bytes, "\(name) changes nothing") }
    }

    @Test func karaokeColorsEveryWordSaidSoFar() {
        // At 2.25 s the fourth word is spoken: karaoke colors three more words than Word Color.
        let word = Self.captioned(at: 2.25) { $0.highlight = .word; $0.highlightColor = RGB(0, 1, 0) }
        let karaoke = Self.captioned(at: 2.25) { $0.highlight = .karaoke; $0.highlightColor = RGB(0, 1, 0) }
        func green(_ b: Bitmap) -> Int {
            var n = 0
            for y in stride(from: 0, to: b.height, by: 2) {
                for x in stride(from: 0, to: b.width, by: 2) { let p = b.pixel(x: x, y: y); if p.g > 200 && p.r < 80 { n += 1 } }
            }
            return n
        }
        #expect(green(karaoke) > 2 * green(word), "\(green(karaoke)) vs \(green(word))")
    }

    @Test func aMissingFontDrawsAsSystem() {
        let missing = Self.captioned(at: 1.85) { $0.font = .family("No Such Font 123"); $0.weight = .semibold }
        let system = Self.captioned(at: 1.85) { $0.weight = .semibold }
        #expect(missing.bytes == system.bytes)
        #expect(Self.captioned(at: 1.85) { $0.font = .family("Helvetica") }.bytes != Self.captioned(at: 1.85).bytes)
    }

    @Test func sampleTileShowsTheStyle() throws {
        let size = CGSize(width: 120, height: 56)
        let classic = try #require(CaptionPainter.sample(CaptionStyle(), size: size))
        let neon = try #require(CaptionPainter.sample(CaptionLook.named("neon")!.style, size: size))
        #expect(classic.width == 120 && classic.height == 56)
        #expect(Bitmap(CIImage(cgImage: classic)).bytes != Bitmap(CIImage(cgImage: neon)).bytes)
    }

    @Test func captionsAreSharpAt4K() {
        // Drawn at the output size, not scaled up: white text on the dark box
        // goes from dark to light within a pixel or two.
        let big = Self.captioned(at: 1.85, size: CGSize(width: 3840, height: 2160))
        var steepest = 0
        // The caption sits 6% up from the bottom; bitmap rows count from the top.
        for y in stride(from: Int(2160 * 0.86), to: Int(2160 * 0.92), by: 3) {
            for x in 1200..<2640 { steepest = max(steepest, abs(big.pixel(x: x + 1, y: y).r - big.pixel(x: x, y: y).r)) }
        }
        #expect(steepest > 150, "a crisp text edge changes fast, got \(steepest) per pixel")
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
