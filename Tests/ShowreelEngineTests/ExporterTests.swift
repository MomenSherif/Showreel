import AVFoundation
import CoreImage
import Foundation
import Testing
@testable import ShowreelEngine
import ShowreelKit

/// The export draws the same frames as the preview (S-036).
@Suite("Exporter", .serialized)
struct ExporterTests {
    static let source = CGSize(width: 320, height: 200)
    static let output = CGSize(width: 640, height: 400)

    /// A 6-second screen.mov: a gradient with a white bar that moves right,
    /// so every second looks different.
    static func makeScreen(size: CGSize = source, seconds: Int = 6) async throws -> URL {
        let source = size, w = Int(size.width), h = Int(size.height)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("export-src-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        for i in 0..<(seconds * 30) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            let t = Double(i) / 30
            let back = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: size.width, y: size.height),
                "inputColor0": CIColor(red: 0.2, green: 0.4, blue: 0.9), "inputColor1": CIColor(red: 0.6, green: 0.2, blue: 0.6),
            ])!.outputImage!
            let bar = CIImage(color: .white).cropped(to: CGRect(x: 20 + t * 40, y: 60, width: 30, height: 80))
            let frame = bar.composited(over: back).cropped(to: CGRect(origin: .zero, size: source))
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            let pixels = try #require(buffer)
            context.render(frame, to: pixels)
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }

    /// The screen drawn with a style, as the editor builds it.
    static func composition(screen url: URL, fps: Int32 = 30, output: CGSize = output) async throws -> (AVComposition, AVVideoComposition) {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let range = try await track.load(.timeRange)
        let composition = AVMutableComposition()
        let screen = try #require(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try screen.insertTimeRange(range, of: track, at: .zero)
        var style = Style()
        style.background = .gradient("sunrise")
        style.padding = 0.08
        style.rounding = 20
        let scene = BubbleScene(bubble: [], fallbackCenter: CGPoint(x: 0.5, y: 0.5), hidden: [], diameter: 0.2)
        var config = AVVideoComposition.Configuration()
        config.customVideoCompositorClass = BubbleCompositor.self
        config.renderSize = output
        config.frameDuration = CMTime(value: 1, timescale: fps)
        config.instructions = [BubbleInstruction(timeRange: CMTimeRange(start: .zero, duration: range.duration),
                                                 screenTrack: screen.trackID, cameraTrack: nil, scene: scene,
                                                 style: RenderStyle(style: style))]
        return (composition.copy() as! AVComposition, AVVideoComposition(configuration: config))
    }

    static func frame(of asset: AVAsset, at t: Double, composition: AVVideoComposition? = nil) async throws -> Bitmap {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = composition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
        return Bitmap(CIImage(cgImage: image))
    }

    @Test func exportedFrameMatchesThePreview() async throws {
        let src = try await Self.makeScreen()
        defer { try? FileManager.default.removeItem(at: src) }
        let (asset, video) = try await Self.composition(screen: src)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }

        let settings = ExportSettings(format: .mp4, resolution: .p720, fps: 30, quality: .high)
        try await Exporter.export(asset: asset, videoComposition: video, settings: settings, to: out) { _ in }

        let exported = AVURLAsset(url: out)
        let duration = try await exported.load(.duration).seconds
        #expect(abs(duration - 6) < 0.1, "the file is \(duration) s")
        let track = try #require(try await exported.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size == Self.output)

        let preview = try await Self.frame(of: asset, at: 5, composition: video)
        let file = try await Self.frame(of: exported, at: 5)
        let ssim = SSIM.mean(preview, file)
        #expect(ssim > 0.98, "SSIM at 5 s is \(ssim)")
        // A different moment must not match as well: the test can fail.
        let other = try await Self.frame(of: exported, at: 1)
        #expect(SSIM.mean(preview, other) < ssim)
    }

    /// S-037 [manual]: a 1-minute 1080p/60 export takes under 30 seconds.
    /// Opt in with SHOWREEL_PERF=1; it makes a 1-minute source first.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHOWREEL_PERF"] != nil))
    func oneMinuteAt1080p60IsFast() async throws {
        let src = try await Self.makeScreen(size: CGSize(width: 2880, height: 1800), seconds: 60)
        defer { try? FileManager.default.removeItem(at: src) }
        let size = CGSize(width: 1728, height: 1080)
        let (asset, video) = try await Self.composition(screen: src, fps: 60, output: size)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("export-perf-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        let start = Date.now
        try await Exporter.export(asset: asset, videoComposition: video, settings: ExportSettings(), to: out) { _ in }
        let seconds = Date.now.timeIntervalSince(start)
        print("PERF 1 min 1080p60 export: \(String(format: "%.1f", seconds)) s")
        #expect(seconds < 30)
    }

    @Test func gifHasEveryFrameAndLoops() async throws {
        let src = try await Self.makeScreen()
        defer { try? FileManager.default.removeItem(at: src) }
        let (asset, video) = try await Self.composition(screen: src, fps: 15)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: out) }

        try await Exporter.export(asset: asset, videoComposition: video, settings: ExportSettings(format: .gif, resolution: .p720, fps: 15),
                                  to: out) { _ in }
        let gif = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        #expect(CGImageSourceGetCount(gif) == 90)
        let props = CGImageSourceCopyProperties(gif, nil) as? [CFString: Any]
        let loop = (props?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int
        #expect(loop == 0)
    }

    @Test func cancellingDeletesThePartialFile() async throws {
        let src = try await Self.makeScreen()
        defer { try? FileManager.default.removeItem(at: src) }
        let (asset, video) = try await Self.composition(screen: src)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).mov")
        let started = AsyncStream<Void>.makeStream()
        let task = Task {
            try await Exporter.export(asset: asset, videoComposition: video, settings: ExportSettings(format: .mov, resolution: .p2160),
                                      to: out) { p in if p > 0 { started.continuation.yield() } }
        }
        for await _ in started.stream { break }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}

/// Structural similarity on luma, over 8 × 8 windows, averaged.
enum SSIM {
    static func mean(_ a: Bitmap, _ b: Bitmap) -> Double {
        precondition(a.width == b.width && a.height == b.height)
        func luma(_ m: Bitmap, _ x: Int, _ y: Int) -> Double {
            let i = (y * m.width + x) * 4
            return 0.299 * Double(m.bytes[i]) + 0.587 * Double(m.bytes[i + 1]) + 0.114 * Double(m.bytes[i + 2])
        }
        let c1: Double = (0.01 * 255) * (0.01 * 255), c2: Double = (0.03 * 255) * (0.03 * 255)
        var total = 0.0, windows = 0
        for wy in stride(from: 0, to: a.height - 7, by: 8) {
            for wx in stride(from: 0, to: a.width - 7, by: 8) {
                var sa = 0.0, sb = 0.0, saa = 0.0, sbb = 0.0, sab = 0.0
                for y in wy..<wy + 8 {
                    for x in wx..<wx + 8 {
                        let p = luma(a, x, y), q = luma(b, x, y)
                        sa += p; sb += q; saa += p * p; sbb += q * q; sab += p * q
                    }
                }
                let n = 64.0
                let ma = sa / n, mb = sb / n
                let va = saa / n - ma * ma, vb = sbb / n - mb * mb, cov = sab / n - ma * mb
                total += ((2 * ma * mb + c1) * (2 * cov + c2)) / ((ma * ma + mb * mb + c1) * (va + vb + c2))
                windows += 1
            }
        }
        return total / Double(max(windows, 1))
    }
}
