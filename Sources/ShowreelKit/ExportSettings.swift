import CoreGraphics
import Foundation

/// What an export makes (S-036): the format, the size, the frame rate, and
/// the quality. The rules for each format and the size estimate live here,
/// with no AVFoundation, so they are unit tested.
public struct ExportSettings: Codable, Equatable, Sendable {
    public enum Format: String, Codable, CaseIterable, Sendable {
        /// H.264 in an MP4: plays everywhere.
        case mp4
        /// HEVC in a QuickTime movie: a smaller file, for Apple devices.
        case mov
        /// An animated GIF: loops, no sound.
        case gif

        public var title: String { rawValue.uppercased() }
        public var fileExtension: String { rawValue }
        public var hasAudio: Bool { self != .gif }

        public var caption: String {
            switch self {
            case .mp4: "Plays everywhere."
            case .mov: "Smaller file, for Apple devices."
            case .gif: "Loops in docs and chats. No sound."
            }
        }
    }

    /// The video's short side in pixels.
    public enum Resolution: Int, Codable, CaseIterable, Sendable {
        case p720 = 720, p1080 = 1080, p2160 = 2160

        public var title: String { self == .p2160 ? "4K" : "\(rawValue)p" }
    }

    public enum Quality: String, Codable, CaseIterable, Sendable {
        case standard, high, best

        public var title: String { rawValue.capitalized }

        /// Bits per pixel per frame for H.264. Screen recordings are mostly
        /// still, so these are lower than for camera video.
        var h264BitsPerPixel: Double {
            switch self {
            case .standard: 0.05
            case .high: 0.08
            case .best: 0.14
            }
        }
    }

    public var format: Format
    public var resolution: Resolution
    public var fps: Int
    public var quality: Quality

    public init(format: Format = .mp4, resolution: Resolution = .p1080, fps: Int = 60, quality: Quality = .high) {
        self.format = format
        self.resolution = resolution
        self.fps = fps
        self.quality = quality
    }

    // MARK: Choices per format

    /// GIFs stay small: no 4K.
    public var resolutions: [Resolution] { format == .gif ? [.p720, .p1080] : Resolution.allCases }

    /// GIF delays are in hundredths of a second and players slow anything
    /// faster than 50 fps, so GIFs offer 15 and 30.
    public var frameRates: [Int] { format == .gif ? [15, 30] : [30, 60] }

    /// The same choices moved onto ones `format` offers: the nearest frame
    /// rate, and 1080p in place of 4K for a GIF.
    public func fitted() -> ExportSettings {
        var s = self
        if !s.resolutions.contains(s.resolution) { s.resolution = s.resolutions.last ?? .p1080 }
        if !s.frameRates.contains(s.fps) {
            s.fps = s.frameRates.min { abs($0 - fps) < abs($1 - fps) } ?? 30
        }
        return s
    }

    /// Switches the format, keeping what still applies.
    public func with(format: Format) -> ExportSettings {
        var s = self
        s.format = format
        // Coming back from a GIF, 30 fps would stay; 60 is the video default.
        if self.format == .gif, format != .gif { s.fps = 60 }
        return s.fitted()
    }

    // MARK: Size

    /// The output size for a canvas: the short side is the resolution, the
    /// shape is the canvas's, and both sides are even (encoders need it).
    public func outputSize(canvas: CGSize) -> CGSize {
        guard canvas.width > 0, canvas.height > 0 else { return .zero }
        let short = CGFloat(resolution.rawValue)
        let scale = short / min(canvas.width, canvas.height)
        func even(_ v: CGFloat) -> CGFloat { max(2, (v / 2).rounded() * 2) }
        return CGSize(width: even(canvas.width * scale), height: even(canvas.height * scale))
    }

    /// True when the export is bigger than the recording, so it looks softer.
    public func isUpscaled(canvas: CGSize) -> Bool {
        CGFloat(resolution.rawValue) > min(canvas.width, canvas.height) + 1
    }

    /// Video bits per second for an output `size`.
    public func videoBitrate(size: CGSize) -> Int {
        let perPixel = quality.h264BitsPerPixel * (format == .mov ? 0.6 : 1) // HEVC needs about 60% for the same look
        return Int(Double(size.width * size.height) * Double(fps) * perPixel)
    }

    public static let audioBitrate = 192_000

    /// About how many bytes the file will have: the bitrates over the length,
    /// or for a GIF, every frame stored on its own.
    public func estimatedBytes(canvas: CGSize, duration: Double, hasAudio: Bool) -> Int64 {
        let size = outputSize(canvas: canvas)
        let seconds = max(duration, 0)
        if format == .gif {
            // Screen content compresses to about a tenth of a byte per pixel.
            return Int64(Double(size.width * size.height) * 0.1 * Double(fps) * seconds)
        }
        let bits = Double(videoBitrate(size: size) + (hasAudio ? Self.audioBitrate : 0)) * seconds
        return Int64(bits / 8)
    }

    /// Each GIF frame's delay in hundredths of a second. Rounding the running
    /// total, not each frame, keeps the GIF as long as the video: 30 fps
    /// becomes 3, 3, 4, 3, 3, 4 …
    public static func gifDelays(frames: Int, fps: Int) -> [Int] {
        guard frames > 0, fps > 0 else { return [] }
        func at(_ i: Int) -> Int { Int((Double(i) * 100 / Double(fps)).rounded()) }
        return (0..<frames).map { at($0 + 1) - at($0) }
    }

    // MARK: Saving

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decode(_ data: Data?) -> ExportSettings {
        data.flatMap { try? JSONDecoder().decode(ExportSettings.self, from: $0) }?.fitted() ?? ExportSettings()
    }
}

/// How long an export has left (S-037), from how long it ran and how far it got.
public enum ExportETA {
    /// Seconds left, or nil until there is enough to go on (a second and 2%).
    public static func secondsLeft(elapsed: Double, fraction: Double) -> Double? {
        guard elapsed >= 1, fraction >= 0.02, fraction < 1 else { return nil }
        return elapsed / fraction * (1 - fraction)
    }

    /// "About 20 seconds left", "About a minute left", "About 3 minutes left".
    public static func text(secondsLeft: Double?) -> String {
        guard let s = secondsLeft else { return "Estimating time left…" }
        if s < 5 { return "Less than 5 seconds left" }
        if s < 55 { return "About \(Int((s / 5).rounded()) * 5) seconds left" }
        let minutes = Int((s / 60).rounded())
        return minutes <= 1 ? "About a minute left" : "About \(minutes) minutes left"
    }
}
