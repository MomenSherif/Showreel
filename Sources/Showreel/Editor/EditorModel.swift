import AVFoundation
import Observation
import SwiftUI
import ShowreelKit

/// The inspector's sections, in the order of the segmented picker (docs/DESIGN.md, "Editor").
enum InspectorSection: String, CaseIterable, Identifiable {
    case background, screen, effects, camera, captions, audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .background: "Background"
        case .screen: "Screen"
        case .effects: "Effects"
        case .camera: "Camera"
        case .captions: "Captions"
        case .audio: "Audio"
        }
    }

    var symbol: String {
        switch self {
        case .background: "photo"
        case .screen: "macwindow"
        case .effects: "cursorarrow.rays"
        case .camera: "person.crop.circle"
        case .captions: "captions.bubble"
        case .audio: "waveform"
        }
    }
}

/// The playhead position, observed only by the time label and the playhead
/// line, because it changes 30 times a second while playing.
@Observable
final class Playhead {
    private(set) var time: Double = 0

    func set(_ time: Double) { self.time = time }
}

/// One editor window's state: the player, the length, and the inspector.
@Observable
final class EditorModel {
    let project: Project
    @ObservationIgnored let playhead = Playhead()
    private(set) var player: AVPlayer?
    private(set) var duration: Double
    private(set) var isPlaying = false
    var section: InspectorSection = .background
    var showsInspector = true

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var rateObserver: NSKeyValueObservation?

    /// The newest Editor, for snapshot mode and the self-test.
    private(set) static weak var newest: EditorModel?

    init(project: Project) {
        self.project = project
        duration = project.duration
    }

    /// Builds the composition and the player. Called once per window.
    func load() async {
        guard player == nil, let item = await PlayerBuilder.item(for: project) else { return }
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        if let length = try? await item.asset.load(.duration).seconds, length > 0 { duration = length }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                // While scrubbing, the playhead shows the target, not the old frame.
                guard let self, !self.isSeeking else { return }
                self.playhead.set(time.seconds)
            }
        }
        rateObserver = player.observe(\.rate) { [weak self] player, _ in
            let playing = player.rate != 0
            Task { @MainActor in self?.isPlaying = playing }
        }
        self.player = player
        Self.newest = self
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            // At the end, play from the start again.
            if playhead.time >= duration - 0.05 { seek(to: 0) }
            player.play()
        }
    }

    // MARK: Seeking (S-016)

    /// The time the newest seek asked for, while one is still running.
    @ObservationIgnored private var seekTarget: Double?
    @ObservationIgnored private var isSeeking = false
    /// How long the newest exact seek took to show its frame, in seconds.
    @ObservationIgnored private(set) var lastSeekDuration: Double = 0

    /// Moves the playhead to `time`. The label and line move at once; the
    /// canvas follows as fast as frames decode. Seeks never pile up: while one
    /// runs, only the newest target is kept (chase seeking).
    func seek(to time: Double) {
        let target = PlayheadMove.clamp(time, duration: duration)
        playhead.set(target)
        seekTarget = target
        if !isSeeking { seekToTarget() }
    }

    private func seekToTarget() {
        guard let player, let target = seekTarget else { isSeeking = false; return }
        isSeeking = true
        seekTarget = nil
        let started = Date.now
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.lastSeekDuration = Date.now.timeIntervalSince(started)
                self?.seekToTarget()
            }
        }
    }

    /// Waits until no seek is running. For the self-test.
    func seeksSettled() async {
        for _ in 0..<200 where isSeeking { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func step(frames: Int) {
        player?.pause()
        seek(to: PlayheadMove.step(from: playhead.time, frames: frames, duration: duration))
    }

    func jump(by seconds: Double) {
        seek(to: PlayheadMove.jump(from: playhead.time, by: seconds, duration: duration))
    }

    func goToStart() { seek(to: 0) }
    func goToEnd() { player?.pause(); seek(to: duration) }

    func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        rateObserver = nil
    }
}
