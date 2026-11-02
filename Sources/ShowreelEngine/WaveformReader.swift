import AVFoundation
import ShowreelKit

/// Reads an audio file's loudness for the audio lane (S-042).
public enum WaveformReader {
    /// Peaks of `url`'s audio, `peaksPerSecond` a second. Nil when it has none.
    public static func read(_ url: URL, peaksPerSecond: Double = 50) async -> Waveform? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let rate = 8_000.0
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        let perPeak = max(1, Int(rate / peaksPerSecond))
        var peaks: [Float] = []
        var current: Float = 0
        var count = 0
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                              dataPointerOut: &pointer) == noErr, let pointer else { continue }
            pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { samples in
                for i in 0..<(length / 4) {
                    current = max(current, abs(samples[i]))
                    count += 1
                    if count == perPeak {
                        peaks.append(min(current, 1))
                        current = 0
                        count = 0
                    }
                }
            }
        }
        if count > 0 { peaks.append(min(current, 1)) }
        return reader.status == .completed ? Waveform(peaksPerSecond: rate / Double(perPeak), peaks: peaks) : nil
    }
}
