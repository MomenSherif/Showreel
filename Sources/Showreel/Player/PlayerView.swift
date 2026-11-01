import AVFoundation
import AVKit
import SwiftData
import SwiftUI
import ShowreelKit

/// One project's window (S-009). In M1 it plays the recording with mic and
/// system audio in sync and the camera in its bubble; M3 turns it into the Editor.
struct ProjectWindow: View {
    let id: UUID
    @Query private var projects: [Project]

    init(id: UUID) {
        self.id = id
        _projects = Query(filter: #Predicate<Project> { $0.uuid == id })
    }

    var body: some View {
        Group {
            if let project = projects.first {
                if ProjectStore.filesMissing(project) {
                    ContentUnavailableView {
                        Label("Recording Files Are Missing", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("The project folder was moved or deleted.")
                    } actions: {
                        Button("Show in Finder") { ProjectStore.showInFinder(project) }
                    }
                } else {
                    PlayerView(project: project)
                }
            } else {
                ContentUnavailableView("Project Not Found", systemImage: "questionmark.square.dashed")
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .navigationTitle(projects.first?.title ?? "Project")
        .noInitialFocus()
    }
}

struct PlayerView: View {
    let project: Project
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Surfaces.canvasBackdrop
            if let player {
                PlayerSurface(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: project.uuid) {
            player = await PlayerBuilder.player(for: project)
        }
        .onDisappear { player?.pause() }
    }
}

/// AVPlayerView: the system transport, with Space, arrow keys, and J/K/L.
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsMagnification = false
        view.setAccessibilityLabel("Playhead")
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

/// Puts the tracks of one project together into a playable item.
@MainActor
enum PlayerBuilder {
    static func player(for project: Project) async -> AVPlayer? {
        guard let item = await item(for: project) else { return nil }
        return AVPlayer(playerItem: item)
    }

    static func item(for project: Project) async -> AVPlayerItem? {
        let id = project.uuid
        let composition = AVMutableComposition()
        let screenAsset = AVURLAsset(url: ProjectStore.file(ProjectFiles.screen, of: id))
        guard let screenSource = try? await screenAsset.loadTracks(withMediaType: .video).first,
              let duration = try? await screenAsset.load(.duration),
              let screenTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        let range = CMTimeRange(start: .zero, duration: duration)
        try? screenTrack.insertTimeRange(range, of: screenSource, at: .zero)
        let natural = (try? await screenSource.load(.naturalSize)) ?? CGSize(width: project.videoWidth, height: project.videoHeight)

        for name in [ProjectFiles.microphone, ProjectFiles.systemAudio] {
            let url = ProjectStore.file(name, of: id)
            guard FileManager.default.fileExists(atPath: url.path),
                  let source = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let length = (try? await source.load(.timeRange).duration) ?? duration
            try? track.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, duration)), of: source, at: .zero)
        }

        var cameraID: CMPersistentTrackID?
        let cameraURL = ProjectStore.file(ProjectFiles.camera, of: id)
        if FileManager.default.fileExists(atPath: cameraURL.path),
           let source = try? await AVURLAsset(url: cameraURL).loadTracks(withMediaType: .video).first,
           let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let length = (try? await source.load(.timeRange).duration) ?? duration
            try? track.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, duration)), of: source, at: .zero)
            cameraID = track.trackID
        }

        let log = (try? Data(contentsOf: ProjectStore.file(ProjectFiles.events, of: id))).flatMap { try? EventLog.decode($0) }
        // The bubble's size on screen, as a share of the recorded width in points.
        let pointWidth = max(1, (log?.source.width ?? natural.width / 2))
        let diameter = (Layout.bubbleSizes[min(max(project.bubbleSize, 0), 2)] - Space.lg) / pointWidth

        let instruction = BubbleInstruction(timeRange: range, screenTrack: screenTrack.trackID, cameraTrack: cameraID,
                                            bubble: log?.bubble ?? [],
                                            fallbackCenter: CGPoint(x: project.bubbleX, y: project.bubbleY),
                                            hidden: log?.cameraHidden ?? [], diameter: diameter)
        var config = AVVideoComposition.Configuration()
        config.customVideoCompositorClass = BubbleCompositor.self
        config.renderSize = natural
        config.frameDuration = CMTime(value: 1, timescale: 60)
        config.instructions = [instruction]

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = AVVideoComposition(configuration: config)
        return item
    }
}
