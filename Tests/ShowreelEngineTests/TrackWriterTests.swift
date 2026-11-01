import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import ShowreelEngine

/// The writer on synthetic frames: what it keeps, what it skips, and what it
/// counts (S-007).
@Suite("Track writer")
struct TrackWriterTests {
    static func frame(width: Int = 64, height: Int = 36) throws -> CMSampleBuffer {
        var pixels: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixels)
        let buffer = try #require(pixels)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0x80, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60), presentationTimeStamp: .zero,
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: try #require(format),
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        return try #require(sample)
    }

    static func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("writer-\(UUID().uuidString).mov")
    }

    @Test func writesFramesAndCountsThem() async throws {
        let timeline = Timeline()
        let url = Self.url()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try TrackWriter(url: url, kind: .video(width: 64, height: 36, bitrate: 1_000_000), timeline: timeline)
        let start = Timeline.hostNow
        let sample = try Self.frame()
        writer.append(sample, host: start - 0.5)          // before the start: skipped, not counted
        timeline.begin(at: start)
        for i in 1...30 {
            writer.append(sample, host: start + Double(i) / 60)
            try await Task.sleep(for: .milliseconds(4))
        }
        writer.append(sample, host: start + 10 / 60)      // out of order: late
        let saved = await writer.finish(at: 1)

        #expect(saved)
        let stats = writer.stats
        // 30 frames plus the newest one repeated at the end.
        #expect(stats == WriterStats(appended: 31, dropped: 0, late: 1), "\(stats)")
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - 1) < 0.05, "file is \(duration) s")
    }

    @Test func pausedFramesAreSkippedNotCounted() async throws {
        let timeline = Timeline()
        let url = Self.url()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try TrackWriter(url: url, kind: .video(width: 64, height: 36, bitrate: 1_000_000), timeline: timeline)
        let start = Timeline.hostNow
        let sample = try Self.frame()
        timeline.begin(at: start)
        writer.append(sample, host: start + 0.1)
        timeline.pause(at: start + 0.2)
        writer.append(sample, host: start + 0.3)          // while paused
        timeline.resume(at: start + 0.4)
        writer.append(sample, host: start + 0.5)          // 0.3 s in recording time
        _ = await writer.finish(at: 0.3)
        #expect(writer.stats == WriterStats(appended: 2, dropped: 0, late: 0), "\(writer.stats)")
    }

    @Test func noSamplesMeansNoFile() async throws {
        let url = Self.url()
        let writer = try TrackWriter(url: url, kind: .audio(channels: 1, bitrate: 64_000), timeline: Timeline())
        #expect(await writer.finish(at: 1) == false)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
