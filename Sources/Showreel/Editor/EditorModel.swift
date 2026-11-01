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
            MainActor.assumeIsolated { self?.playhead.set(time.seconds) }
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
            if playhead.time >= duration - 0.05 { player.seek(to: .zero) }
            player.play()
        }
    }

    func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        rateObserver = nil
    }
}
