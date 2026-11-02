import Foundation
import Testing
@testable import ShowreelKit

@Suite("Audio mix")
struct AudioMixTests {
    /// S-042: Mute Section mutes a range, and again unmutes it.
    @Test func muteSectionToggles() {
        var mix = AudioMix()
        mix.toggleMute(from: 2, to: 4)
        #expect(mix.muted == [.init(start: 2, end: 4)])
        #expect(mix.isMuted(from: 2.5, to: 3.5))
        mix.toggleMute(from: 2, to: 4)
        #expect(mix.muted.isEmpty)
    }

    @Test func touchingSpansJoin() {
        var mix = AudioMix()
        mix.mute(from: 1, to: 2)
        mix.mute(from: 5, to: 6)
        mix.mute(from: 2, to: 3)
        #expect(mix.muted == [.init(start: 1, end: 3), .init(start: 5, end: 6)])
        mix.mute(from: 2.5, to: 5.5)
        #expect(mix.muted == [.init(start: 1, end: 6)])
    }

    @Test func unmutingTheMiddleLeavesTheEnds() {
        var mix = AudioMix(muted: [.init(start: 0, end: 10)])
        mix.toggleMute(from: 4, to: 6)
        #expect(mix.muted == [.init(start: 0, end: 4), .init(start: 6, end: 10)])
    }

    @Test func aPartlyMutedRangeIsMutedWhole() {
        var mix = AudioMix(muted: [.init(start: 0, end: 3)])
        mix.toggleMute(from: 2, to: 5)
        #expect(mix.muted == [.init(start: 0, end: 5)])
    }

    @Test func volumesStayInRange() {
        var mix = AudioMix()
        mix.setVolume(3, of: .microphone)
        mix.setVolume(-1, of: .systemAudio)
        #expect(mix.volume(of: .microphone) == 2)
        #expect(mix.volume(of: .systemAudio) == 0)
    }

    /// Muted spans are in source time: a cut before one moves it earlier.
    @Test func mutedRangesFollowTheCut() throws {
        var edits = EditList(sourceDuration: 10)
        _ = edits.split(atEditTime: 1)
        _ = edits.split(atEditTime: 3)
        let middle = try #require(edits.segments.dropFirst().first)
        _ = edits.delete(middle.id)
        let mix = AudioMix(muted: [.init(start: 5, end: 6)])
        let ranges = mix.mutedEditRanges(in: edits)
        #expect(ranges.count == 1)
        #expect(abs((ranges.first?.lowerBound ?? 0) - 3) < 0.0001)
    }

    @Test func mixRoundTripsAndOldDataLoads() {
        var mix = AudioMix(microphone: 1.4, systemAudio: 0.5)
        mix.mute(from: 1, to: 2)
        #expect(AudioMix.decode(mix.encoded()) == mix)
        #expect(AudioMix.decode(nil) == AudioMix())
        #expect(AudioMix.decode(Data(#"{"microphone":0.5}"#.utf8)).microphone == 0.5)
    }

    @Test func waveformPeakOverATimeSpan() {
        let wave = Waveform(peaksPerSecond: 10, peaks: [0.1, 0.5, 0.2, 0.9, 0.3])
        #expect(wave.peak(from: 0, to: 0.2) == 0.5)
        #expect(wave.peak(from: 0.25, to: 0.4) == 0.9)
        #expect(wave.peak(from: 2, to: 3) == 0)
    }
}
