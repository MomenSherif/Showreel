import AppKit
import AVFoundation
import SwiftData
import ShowreelKit

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with the projects named in docs/STORIES.md, each with a thumbnail and
/// a short screen.mov, as a real recording would leave. Seed only what a
/// person can create in the app.
@MainActor
enum SeedData {
    struct Sample {
        let title: String
        let duration: Double
        let hue: CGFloat
        let ageHours: Double
    }

    static let samples = [
        Sample(title: "Onboarding walkthrough", duration: 42, hue: 0.62, ageHours: 2),
        Sample(title: "Pricing page tour", duration: 75, hue: 0.78, ageHours: 26),
        Sample(title: "API keys demo", duration: 28, hue: 0.45, ageHours: 80),
    ]

    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.context
        guard ((try? context.fetchCount(FetchDescriptor<Project>())) ?? 0) == 0 else { return }
        try? FileManager.default.removeItem(at: ProjectStore.root)
        for sample in samples {
            let project = Project(title: sample.title, duration: sample.duration)
            project.createdAt = Date.now.addingTimeInterval(-sample.ageHours * 3_600)
            project.videoWidth = 1600
            project.videoHeight = 1000
            project.sourceName = "Built-in Retina Display"
            context.insert(project)
            _ = try? ProjectStore.makeFolder(for: project.uuid)
            let image = frame(hue: sample.hue)
            write(image, to: ProjectStore.file(ProjectFiles.thumbnail, of: project.uuid))
            writeMovie(image, seconds: 2, to: ProjectStore.file(ProjectFiles.screen, of: project.uuid))
        }
        try? context.save()
    }

    /// A desktop with one app window, like a frame of a real recording.
    static func frame(hue: CGFloat, size: CGSize = CGSize(width: 1600, height: 1000)) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let top = NSColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1).cgColor
        let bottom = NSColor(hue: hue + 0.08, saturation: 0.7, brightness: 0.6, alpha: 1).cgColor
        let gradient = CGGradient(colorsSpace: nil, colors: [top, bottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        let window = CGRect(x: 160, y: 110, width: 1280, height: 780)
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(NSColor(white: 0.98, alpha: 1).cgColor)
        ctx.addPath(CGPath(roundedRect: window, cornerWidth: 20, cornerHeight: 20, transform: nil))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0)
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: window.minX + 24 + CGFloat(i) * 26, y: window.maxY - 38, width: 16, height: 16))
        }
        ctx.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
        ctx.fill(CGRect(x: window.minX, y: window.minY, width: 260, height: window.height - 56))
        ctx.setFillColor(NSColor(hue: hue, saturation: 0.6, brightness: 0.85, alpha: 1).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: window.minX + 300, y: window.maxY - 150, width: 420, height: 44),
                           cornerWidth: 10, cornerHeight: 10, transform: nil)) // grid: ok pixels in a sample image
        ctx.fillPath()
        ctx.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
        for row in 0..<6 {
            let y = window.maxY - 230 - CGFloat(row) * 80
            ctx.addPath(CGPath(roundedRect: CGRect(x: window.minX + 300, y: y, width: CGFloat(880 - row * 70), height: 24),
                               cornerWidth: 6, cornerHeight: 6, transform: nil)) // grid: ok pixels in a sample image
            ctx.fillPath()
        }
        return ctx.makeImage()!
    }

    private static func write(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])?.write(to: url)
    }

    /// A short H.264 movie that shows `image`, so the player has a real file.
    private static func writeMovie(_ image: CGImage, seconds: Int, to url: URL) {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: image.width, AVVideoHeightKey: image.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: image.width, kCVPixelBufferHeightKey as String: image.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { return }
        for i in 0...(seconds * 10) {
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 10))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { @Sendable in done.signal() } // runs on a background queue
        done.wait()
    }
}
