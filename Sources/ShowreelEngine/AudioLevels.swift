import AVFoundation

/// The volumes and muted parts of a composition's audio tracks (S-042), as
/// plain values, so they cross to the exporter's thread. `audioMix()` makes
/// the AVAudioMix that the preview and the export both play.
public struct AudioLevels: Equatable, Sendable {
    public struct Track: Equatable, Sendable {
        public var trackID: CMPersistentTrackID
        public var volume: Float

        public init(trackID: CMPersistentTrackID, volume: Float) {
            self.trackID = trackID
            self.volume = volume
        }
    }

    public var tracks: [Track]
    /// Silent parts, in the composition's time (edit time).
    public var muted: [ClosedRange<Double>]
    /// Seconds a mute fades in and out, so it never clicks.
    public static let ramp = 0.03

    public init(tracks: [Track], muted: [ClosedRange<Double>]) {
        self.tracks = tracks
        self.muted = muted
    }

    public func audioMix() -> AVAudioMix {
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.map { track in
            let parameters = AVMutableAudioMixInputParameters()
            parameters.trackID = track.trackID
            parameters.setVolume(track.volume, at: .zero)
            for range in muted {
                parameters.setVolumeRamp(fromStartVolume: track.volume, toEndVolume: 0,
                                         timeRange: CMTimeRange(start: Self.time(max(0, range.lowerBound - Self.ramp)),
                                                                end: Self.time(range.lowerBound)))
                parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: track.volume,
                                         timeRange: CMTimeRange(start: Self.time(range.upperBound),
                                                                end: Self.time(range.upperBound + Self.ramp)))
            }
            return parameters
        }
        return mix
    }

    private static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60_000) }
}
