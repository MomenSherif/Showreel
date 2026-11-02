import CoreGraphics
import Testing
@testable import ShowreelKit

/// Export choices, sizes, and the size estimate (S-036).
@Suite("Export settings")
struct ExportSettingsTests {
    @Test func shortSideIsTheResolution() {
        let wide = ExportSettings(resolution: .p1080)
        #expect(wide.outputSize(canvas: CGSize(width: 2880, height: 1620)) == CGSize(width: 1920, height: 1080))
        #expect(wide.outputSize(canvas: CGSize(width: 1000, height: 1000)) == CGSize(width: 1080, height: 1080))
        // Portrait: the width is the short side.
        #expect(wide.outputSize(canvas: CGSize(width: 1080, height: 1920)) == CGSize(width: 1080, height: 1920))
        // 16:10 at 4K: both sides even.
        let size = ExportSettings(resolution: .p2160).outputSize(canvas: CGSize(width: 3024, height: 1890))
        #expect(size == CGSize(width: 3456, height: 2160))
    }

    @Test func upscalingIsNoticed() {
        #expect(ExportSettings(resolution: .p2160).isUpscaled(canvas: CGSize(width: 2880, height: 1800)))
        #expect(!ExportSettings(resolution: .p1080).isUpscaled(canvas: CGSize(width: 2880, height: 1800)))
        #expect(!ExportSettings(resolution: .p1080).isUpscaled(canvas: CGSize(width: 1920, height: 1080)))
    }

    @Test func gifOffersItsOwnChoices() {
        let gif = ExportSettings(resolution: .p2160, fps: 60).with(format: .gif)
        #expect(gif.resolution == .p1080)
        #expect(gif.fps == 30)
        #expect(gif.frameRates == [15, 30])
        // Back to MP4: 60 fps again, the resolution kept.
        let back = gif.with(format: .mp4)
        #expect(back.fps == 60 && back.resolution == .p1080)
    }

    @Test func gifDelaysKeepTheLength() {
        let delays = ExportSettings.gifDelays(frames: 30, fps: 30)
        #expect(delays.reduce(0, +) == 100)
        #expect(Set(delays) == [3, 4])
        #expect(ExportSettings.gifDelays(frames: 15, fps: 15).reduce(0, +) == 100)
    }

    @Test func estimateFollowsTheChoices() {
        let canvas = CGSize(width: 2880, height: 1800)
        let high = ExportSettings(format: .mp4, resolution: .p1080, fps: 60, quality: .high)
        let bytes = high.estimatedBytes(canvas: canvas, duration: 42, hasAudio: true)
        // 1728 × 1080 × 60 × 0.08 bits ≈ 9 Mbit/s, plus 192 kbit/s of sound, for 42 s ≈ 48 MB.
        #expect(bytes > 40_000_000 && bytes < 55_000_000, "\(bytes)")
        #expect(ExportSettings(format: .mov, quality: .high).estimatedBytes(canvas: canvas, duration: 42, hasAudio: true) < bytes)
        #expect(ExportSettings(format: .mp4, quality: .best).estimatedBytes(canvas: canvas, duration: 42, hasAudio: true) > bytes)
        #expect(ExportSettings(format: .mp4, fps: 30).estimatedBytes(canvas: canvas, duration: 42, hasAudio: true) < bytes)
        #expect(high.estimatedBytes(canvas: canvas, duration: 0, hasAudio: true) == 0)
    }

    @Test func savedSettingsComeBack() {
        let s = ExportSettings(format: .mov, resolution: .p2160, fps: 30, quality: .best)
        #expect(ExportSettings.decode(s.encoded()) == s)
        #expect(ExportSettings.decode(nil) == ExportSettings())
    }
}

/// Time left while exporting (S-037).
@Suite("Export time left")
struct ExportETATests {
    @Test func waitsForEnoughToGoOn() {
        #expect(ExportETA.secondsLeft(elapsed: 0.5, fraction: 0.3) == nil)
        #expect(ExportETA.secondsLeft(elapsed: 3, fraction: 0.01) == nil)
        #expect(ExportETA.text(secondsLeft: nil) == "Estimating time left…")
    }

    @Test func extrapolatesTheRate() {
        // A quarter done in 5 s: 15 s to go.
        #expect(ExportETA.secondsLeft(elapsed: 5, fraction: 0.25) == 15)
    }

    @Test func roundsToFriendlySteps() {
        #expect(ExportETA.text(secondsLeft: 3) == "Less than 5 seconds left")
        #expect(ExportETA.text(secondsLeft: 18) == "About 20 seconds left")
        #expect(ExportETA.text(secondsLeft: 58) == "About a minute left")
        #expect(ExportETA.text(secondsLeft: 170) == "About 3 minutes left")
    }
}
