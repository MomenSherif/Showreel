import Foundation

/// The two audio tracks a recording can have.
public enum AudioSource: String, Codable, CaseIterable, Sendable {
    case microphone, systemAudio

    public var file: String { self == .microphone ? ProjectFiles.microphone : ProjectFiles.systemAudio }
}

/// How the audio plays (S-042): a volume per track and the muted parts.
/// Stored as JSON in `Project.audioData`. Muted spans are in source time, like
/// zooms and captions, so a cut shifts them for free.
public struct AudioMix: Codable, Equatable, Sendable {
    public struct Span: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double

        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }
    }

    /// 0...2: 1 is as recorded.
    public var microphone: Double = 1
    public var systemAudio: Double = 1
    /// Sorted, never overlapping or touching.
    public private(set) var muted: [Span] = []

    public static let volumeRange: ClosedRange<Double> = 0...2

    public init(microphone: Double = 1, systemAudio: Double = 1, muted: [Span] = []) {
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.muted = []
        for span in muted { mute(from: span.start, to: span.end) }
    }

    public func volume(of source: AudioSource) -> Double {
        let v = source == .microphone ? microphone : systemAudio
        return min(max(v, Self.volumeRange.lowerBound), Self.volumeRange.upperBound)
    }

    public mutating func setVolume(_ volume: Double, of source: AudioSource) {
        let v = min(max(volume, Self.volumeRange.lowerBound), Self.volumeRange.upperBound)
        if source == .microphone { microphone = v } else { systemAudio = v }
    }

    /// True when all of `start...end` is muted.
    public func isMuted(from start: Double, to end: Double) -> Bool {
        muted.contains { $0.start <= start + 0.0001 && $0.end >= end - 0.0001 }
    }

    /// Mutes `start...end`, joining spans it touches.
    public mutating func mute(from start: Double, to end: Double) {
        guard end > start else { return }
        var new = Span(start: start, end: end)
        var kept: [Span] = []
        for span in muted {
            if span.end < new.start || span.start > new.end {
                kept.append(span)
            } else {
                new = Span(start: min(span.start, new.start), end: max(span.end, new.end))
            }
        }
        muted = (kept + [new]).sorted { $0.start < $1.start }
    }

    /// Unmutes `start...end`, cutting spans that reach past it.
    public mutating func unmute(from start: Double, to end: Double) {
        guard end > start else { return }
        muted = muted.flatMap { span -> [Span] in
            guard span.end > start, span.start < end else { return [span] }
            var parts: [Span] = []
            if span.start < start { parts.append(Span(start: span.start, end: start)) }
            if span.end > end { parts.append(Span(start: end, end: span.end)) }
            return parts
        }
    }

    /// Mute Section: mutes `start...end`, or unmutes it when all of it is muted.
    public mutating func toggleMute(from start: Double, to end: Double) {
        if isMuted(from: start, to: end) { unmute(from: start, to: end) } else { mute(from: start, to: end) }
    }

    public mutating func unmuteAll() { muted = [] }

    /// The muted parts of the edited video, in edit time.
    public func mutedEditRanges(in edits: EditList) -> [ClosedRange<Double>] {
        muted.flatMap { edits.editRanges(fromSource: $0.start, to: $0.end) }
    }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// The stored mix, or as recorded for a project that has none.
    public static func decode(_ data: Data?) -> AudioMix {
        guard let data, let mix = try? JSONDecoder().decode(AudioMix.self, from: data) else { return AudioMix() }
        return mix
    }

    enum CodingKeys: String, CodingKey { case microphone, systemAudio, muted }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(microphone: (try? c.decodeIfPresent(Double.self, forKey: .microphone)) ?? 1,
                  systemAudio: (try? c.decodeIfPresent(Double.self, forKey: .systemAudio)) ?? 1,
                  muted: (try? c.decodeIfPresent([Span].self, forKey: .muted)) ?? [])
    }
}

/// A track's loudness over time, for the audio lane (S-042): the peak of
/// each short slice, 0...1.
public struct Waveform: Equatable, Sendable {
    public var peaksPerSecond: Double
    public var peaks: [Float]

    public init(peaksPerSecond: Double, peaks: [Float]) {
        self.peaksPerSecond = peaksPerSecond
        self.peaks = peaks
    }

    /// The loudest peak from source time `start` to `end`; 0 outside the track.
    public func peak(from start: Double, to end: Double) -> Float {
        guard peaksPerSecond > 0, !peaks.isEmpty else { return 0 }
        let a = max(0, Int((start * peaksPerSecond).rounded(.down)))
        let b = min(peaks.count, max(a + 1, Int((end * peaksPerSecond).rounded(.up))))
        guard a < b else { return 0 }
        return peaks[a..<b].max() ?? 0
    }
}
