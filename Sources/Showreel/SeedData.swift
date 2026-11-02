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
            writeMovie(image, seconds: Int(sample.duration), to: ProjectStore.file(ProjectFiles.screen, of: project.uuid))
            // Clicks and typing like a real walkthrough's, so the Editor makes zooms from them (S-030).
            try? events(duration: sample.duration).encoded().write(to: ProjectStore.file(ProjectFiles.events, of: project.uuid))
            // The first sample was recorded with the camera on (S-028 snapshots show it).
            if sample.title == samples[0].title {
                project.hasCamera = true
                writeMovie(cameraFrame(), seconds: Int(sample.duration), to: ProjectStore.file(ProjectFiles.camera, of: project.uuid))
                // …and the mic, with captions made from it (S-039).
                project.hasMicrophone = true
                speak(narrationScript, to: ProjectStore.file(ProjectFiles.microphone, of: project.uuid))
                project.captionsData = CaptionTrack(captions: CaptionTrack.lines(from: narrationWords), language: "en_US").encoded()
                // A blur over the first row of the page, as if it held an email (S-048).
                project.blursData = BlurTrack(regions: [
                    BlurRegion(start: 4, end: 9, rect: CropRect(x: 0.28, y: 0.3, width: 0.57, height: 0.06)), // grid: ok normalized
                ]).encoded()
            }
        }
        // Two presets, as a person would save them (S-029).
        var launch = Style()
        launch.background = .gradient("ember")
        launch.padding = 0.1
        launch.frame = .macBook
        model.savePreset(named: "Launch video", style: launch)
        var docs = Style()
        docs.background = .gradient("paper")
        docs.frame = .browser
        docs.effectAmount = 0.3
        model.savePreset(named: "Docs", style: docs)
        try? context.save()
    }

    /// What the first sample's narrator says, and when each sentence starts.
    static let narration: [(start: Double, text: String)] = [
        (1.0, "Welcome to the new onboarding flow."),
        (4.5, "First, click Create Workspace and give it a name your team will recognize."),
        (13.0, "Next, invite a teammate by typing their email address."),
        (20.0, "You can change their role at any time from the members page."),
        (28.0, "Then pick a plan, and you are ready to go."),
        (35.0, "That is the whole setup, in under a minute."),
    ]

    /// The narration for `say`, with a silence before each sentence so it
    /// starts near its caption (`say` speaks about a third of a second a word).
    static var narrationScript: String {
        var at = 0.0
        return narration.map { sentence in
            let pause = max(0, sentence.start - at)
            at = sentence.start + Double(sentence.text.split(separator: " ").count) * 0.34
            return "[[slnc \(Int(pause * 1000))]] \(sentence.text)"
        }.joined(separator: " ")
    }

    /// The narration's words, a third of a second each.
    static var narrationWords: [CaptionWord] {
        narration.flatMap { sentence in
            sentence.text.split(separator: " ").enumerated().map { i, word in
                let start = sentence.start + Double(i) * 0.34
                return CaptionWord(text: String(word), start: start, end: start + 0.3)
            }
        }
    }

    /// A spoken mic track, made with `say`.
    private static func speak(_ text: String, to url: URL) {
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "--data-format=aac", text]
        try? say.run()
        say.waitUntilExit()
    }

    /// Clicks, a typing burst, and the cursor, spread over the recording.
    static func events(duration: Double) -> EventLog {
        var log = EventLog(source: CGRect(x: 0, y: 0, width: 800, height: 500))
        let clicks: [(Double, Double, Double)] = [
            (0.10, 0.30, 0.25), (0.13, 0.36, 0.28), (0.30, 0.70, 0.40), (0.66, 0.60, 0.70), (0.69, 0.62, 0.66), (0.86, 0.22, 0.78),
        ]
        log.clicks = clicks.map { .init(t: $0.0 * duration, x: $0.1, y: $0.2, button: .left) }
        let typing = 0.45 * duration
        log.keys = (0..<14).map { .init(t: typing + Double($0) * 0.18, keyCode: 0) }
        log.caret = [.init(t: typing + 0.1, x: 0.42, y: 0.58), .init(t: typing + 2, x: 0.5, y: 0.58)]
        // Text fields while typing, a link before the last click.
        log.cursorShapes = [.init(t: 0, kind: .arrow), .init(t: typing - 0.5, kind: .iBeam),
                            .init(t: typing + 3, kind: .arrow), .init(t: 0.84 * duration, kind: .pointer)]
        // The cursor moves to each click and the caret, as a hand would; the
        // drawn cursor glides between these points.
        let stops = [(0.0, 0.5, 0.5)] + clicks.map { ($0.0 * duration, $0.1, $0.2) }
            + [(typing - 0.6, 0.44, 0.6), (typing + 3, 0.5, 0.62)]
        log.cursor = stops.sorted { $0.0 < $1.0 }.flatMap { stop in
            // Arrive a little early and rest there, like a real cursor.
            [EventLog.Point(t: max(0, stop.0 - 0.35), x: stop.1, y: stop.2), EventLog.Point(t: stop.0, x: stop.1, y: stop.2)]
        }
        return log
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

    /// A camera frame: a person's head and shoulders on a soft wall, as plain shapes.
    static func cameraFrame(size: CGSize = CGSize(width: 1280, height: 720)) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let wall = CGGradient(colorsSpace: nil, colors: [NSColor(calibratedRed: 0.86, green: 0.82, blue: 0.76, alpha: 1).cgColor,
                                                         NSColor(calibratedRed: 0.70, green: 0.66, blue: 0.62, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1])!
        ctx.drawLinearGradient(wall, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])
        let cx = size.width / 2
        ctx.setFillColor(NSColor(calibratedRed: 0.22, green: 0.33, blue: 0.52, alpha: 1).cgColor)  // sweater
        ctx.fillEllipse(in: CGRect(x: cx - 260, y: -220, width: 520, height: 440))
        ctx.setFillColor(NSColor(calibratedRed: 0.87, green: 0.68, blue: 0.56, alpha: 1).cgColor)  // face
        ctx.fillEllipse(in: CGRect(x: cx - 105, y: 230, width: 210, height: 250)) // grid: ok pixels in a sample image
        ctx.setFillColor(NSColor(calibratedRed: 0.25, green: 0.17, blue: 0.12, alpha: 1).cgColor)  // hair
        ctx.addPath(CGPath(ellipseIn: CGRect(x: cx - 115, y: 380, width: 230, height: 130), transform: nil)) // grid: ok pixels in a sample image
        ctx.fillPath()
        return ctx.makeImage()!
    }

    private static func write(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])?.write(to: url)
    }

    /// An H.264 movie as long as the sample that shows `image`, at 2 fps
    /// to keep seeding fast, so the Editor has a real file.
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
        for i in 0...(seconds * 2) {
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
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 2))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { @Sendable in done.signal() } // runs on a background queue
        done.wait()
    }
}
