import AVFoundation
import SwiftData
import ShowreelEngine
import ShowreelKit

/// Puts the tracks of one project together into a playable item.
@MainActor
enum PlayerBuilder {
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
        let diameter = Layout.bubbleSizes[min(max(project.bubbleSize, 0), 2)] / pointWidth

        let scene = BubbleScene(bubble: log?.bubble ?? [],
                                fallbackCenter: CGPoint(x: project.bubbleX, y: project.bubbleY),
                                hidden: log?.cameraHidden ?? [], diameter: diameter,
                                cornerRatio: project.bubbleShape == BubbleStyle.Shape.roundedSquare.rawValue
                                    ? Radius.bubbleSquareRatio : 0.5)
        let instruction = BubbleInstruction(timeRange: range, screenTrack: screenTrack.trackID, cameraTrack: cameraID,
                                            scene: scene)
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
