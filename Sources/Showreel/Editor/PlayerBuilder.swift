import AVFoundation
import SwiftData
import ShowreelEngine
import ShowreelKit

/// One project's source tracks, loaded once. `item(for:)` puts them
/// together for an edit list, quickly enough to run after every edit.
@MainActor
struct PlayerSources {
    /// A source track and the time it covers.
    /// Holds its asset too: a track whose asset is gone cannot be inserted.
    struct Track {
        let asset: AVURLAsset
        let track: AVAssetTrack
        let range: CMTimeRange

        static func load(_ url: URL, _ media: AVMediaType) async -> Track? {
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: media).first,
                  let range = try? await track.load(.timeRange) else { return nil }
            return Track(asset: asset, track: track, range: range)
        }
    }

    let screen: Track
    let audio: [Track]
    let camera: Track?
    let naturalSize: CGSize
    /// Length of screen.mov, in seconds.
    let duration: Double
    let scene: BubbleScene

    /// Loads the files in the project's folder. Nil when screen.mov cannot be read.
    static func load(for project: Project) async -> PlayerSources? {
        let id = project.uuid
        guard let screen = await Track.load(ProjectStore.file(ProjectFiles.screen, of: id), .video),
              case let duration = screen.range.end.seconds, duration > 0 else { return nil }
        let natural = (try? await screen.track.load(.naturalSize)) ?? CGSize(width: project.videoWidth, height: project.videoHeight)

        var audio: [Track] = []
        for name in [ProjectFiles.microphone, ProjectFiles.systemAudio] {
            let url = ProjectStore.file(name, of: id)
            guard FileManager.default.fileExists(atPath: url.path),
                  let track = await Track.load(url, .audio)
            else { continue }
            audio.append(track)
        }
        let cameraURL = ProjectStore.file(ProjectFiles.camera, of: id)
        let camera = FileManager.default.fileExists(atPath: cameraURL.path)
            ? await Track.load(cameraURL, .video) : nil

        let log = (try? Data(contentsOf: ProjectStore.file(ProjectFiles.events, of: id))).flatMap { try? EventLog.decode($0) }
        // The bubble's size on screen, as a share of the recorded width in points.
        let pointWidth = max(1, (log?.source.width ?? natural.width / 2))
        let diameter = Layout.bubbleSizes[min(max(project.bubbleSize, 0), 2)] / pointWidth
        let scene = BubbleScene(bubble: log?.bubble ?? [],
                                fallbackCenter: CGPoint(x: project.bubbleX, y: project.bubbleY),
                                hidden: log?.cameraHidden ?? [], diameter: diameter,
                                cornerRatio: project.bubbleShape == BubbleStyle.Shape.roundedSquare.rawValue
                                    ? Radius.bubbleSquareRatio : 0.5)
        return PlayerSources(screen: screen, audio: audio, camera: camera, naturalSize: natural, duration: duration, scene: scene)
    }

    /// One kept segment's place in a built item: what its instruction needs.
    struct Slot {
        let timeRange: CMTimeRange
        let screenTrack: CMPersistentTrackID
        let cameraTrack: CMPersistentTrackID?
        let sourceOffset: Double
    }

    /// The kept segments, one after another, drawn with `style`. The slots
    /// let a style change swap the video composition without rebuilding the item.
    func item(for edits: EditList, style: RenderStyle) -> (item: AVPlayerItem, slots: [Slot]) {
        let composition = AVMutableComposition()
        let screenTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTracks = audio.map { ($0, composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)) }
        let cameraTrack = camera.map { ($0, composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)) }

        var slots: [Slot] = []
        var at = CMTime.zero
        for segment in edits.segments {
            // Seconds round to the nearest tick: keep the range inside screen.mov,
            // or the instructions would cover more than the composition holds.
            let range = CMTimeRange(start: Self.time(segment.start), end: Self.time(segment.end)).intersection(screen.range)
            guard !range.isEmpty else { continue }
            try? screenTrack?.insertTimeRange(range, of: screen.track, at: at)
            // Audio and camera files can be a little shorter than the screen:
            // insert only what they have.
            for (source, track) in audioTracks { Self.insert(range, of: source, into: track, at: at) }
            if let (source, track) = cameraTrack { Self.insert(range, of: source, into: track, at: at) }
            if let screenTrack {
                slots.append(Slot(timeRange: CMTimeRange(start: at, duration: range.duration), screenTrack: screenTrack.trackID,
                                  cameraTrack: cameraTrack?.1?.trackID, sourceOffset: segment.start - at.seconds))
            }
            at = at + range.duration
        }
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition(slots: slots, style: style)
        return (item, slots)
    }

    /// How every frame is drawn: the slots with the bubble scene and `style`.
    func videoComposition(slots: [Slot], style: RenderStyle) -> AVVideoComposition {
        var config = AVVideoComposition.Configuration()
        config.customVideoCompositorClass = BubbleCompositor.self
        // The canvas's shape follows the style's aspect ratio (S-027).
        config.renderSize = CanvasLayout.canvasSize(for: style.style, source: naturalSize)
        config.frameDuration = CMTime(value: 1, timescale: 60)
        config.instructions = slots.map {
            BubbleInstruction(timeRange: $0.timeRange, screenTrack: $0.screenTrack, cameraTrack: $0.cameraTrack,
                              scene: scene, sourceOffset: $0.sourceOffset, style: style)
        }
        return AVVideoComposition(configuration: config)
    }

    private static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60_000) }

    private static func insert(_ range: CMTimeRange, of source: Track, into track: AVMutableCompositionTrack?, at: CMTime) {
        let available = source.range.intersection(range)
        guard let track, !available.isEmpty else { return }
        try? track.insertTimeRange(available, of: source.track, at: at + (available.start - range.start))
    }
}
