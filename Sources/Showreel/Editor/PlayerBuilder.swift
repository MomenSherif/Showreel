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
    /// The mic and system audio that were recorded, in that order.
    let audio: [(source: AudioSource, track: Track)]
    /// The mic with its noise removed, once Reduce Noise made it (S-043).
    var cleanMicrophone: Track?
    let camera: Track?
    let naturalSize: CGSize
    /// Length of screen.mov, in seconds.
    let duration: Double
    let scene: BubbleScene
    /// events.json: clicks, keys, and the cursor. Nil when it is missing.
    let events: EventLog?

    /// Loads the files in the project's folder. Nil when screen.mov cannot be read.
    static func load(for project: Project) async -> PlayerSources? {
        let id = project.uuid
        guard let screen = await Track.load(ProjectStore.file(ProjectFiles.screen, of: id), .video),
              case let duration = screen.range.end.seconds, duration > 0 else { return nil }
        let natural = (try? await screen.track.load(.naturalSize)) ?? CGSize(width: project.videoWidth, height: project.videoHeight)

        var audio: [(source: AudioSource, track: Track)] = []
        for source in AudioSource.allCases {
            let url = ProjectStore.file(source.file, of: id)
            guard FileManager.default.fileExists(atPath: url.path),
                  let track = await Track.load(url, .audio)
            else { continue }
            audio.append((source, track))
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
                                    ? Radius.bubbleSquareRatio : 0.5,
                                cursor: CursorPath(log?.cursor ?? []))
        let cleanURL = ProjectStore.file(ProjectFiles.cleanMicrophone, of: id)
        let clean = FileManager.default.fileExists(atPath: cleanURL.path) ? await Track.load(cleanURL, .audio) : nil
        return PlayerSources(screen: screen, audio: audio, cleanMicrophone: clean, camera: camera, naturalSize: natural,
                             duration: duration, scene: scene, events: log)
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
    func item(for edits: EditList, style: RenderStyle, mix: AudioMix) -> (item: AVPlayerItem, slots: [Slot]) {
        let (composition, slots) = composition(for: edits, reducesNoise: mix.reducesNoise)
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition(slots: slots, style: style)
        item.audioMix = audioLevels(for: composition, edits: edits, mix: mix).audioMix()
        return (item, slots)
    }

    /// Each track at its volume, silent in the muted parts (S-042). The
    /// preview and the export both play `audioMix()` of these levels, so
    /// they sound the same.
    func audioLevels(for composition: AVComposition, edits: EditList, mix: AudioMix) -> AudioLevels {
        let tracks = composition.tracks.filter { $0.mediaType == .audio }
        return AudioLevels(tracks: zip(audio, tracks).map { source, track in
                               AudioLevels.Track(trackID: track.trackID, volume: Float(mix.volume(of: source.source)))
                           },
                           muted: mix.mutedEditRanges(in: edits))
    }

    /// The kept segments, one after another, with the slots that say where
    /// each one landed. The preview plays it; the export reads a copy.
    /// With `reducesNoise`, the mic plays from its clean copy when there is one.
    func composition(for edits: EditList, reducesNoise: Bool = false) -> (composition: AVMutableComposition, slots: [Slot]) {
        let composition = AVMutableComposition()
        let screenTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTracks = audio.map { (playing($0, reducesNoise: reducesNoise), composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)) }
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
        return (composition, slots)
    }

    /// The file a track plays from: the clean mic when Reduce Noise is on and it was made.
    func playing(_ entry: (source: AudioSource, track: Track), reducesNoise: Bool) -> Track {
        guard entry.source == .microphone, reducesNoise, let cleanMicrophone else { return entry.track }
        return cleanMicrophone
    }

    /// How every frame is drawn: the slots with the bubble scene and `style`.
    /// The preview draws at the canvas size; an export passes its own size
    /// and frame rate (S-036), and `Renderer` scales to it.
    func videoComposition(slots: [Slot], style: RenderStyle, renderSize: CGSize? = nil, fps: Int = 60) -> AVVideoComposition {
        var config = AVVideoComposition.Configuration()
        config.customVideoCompositorClass = BubbleCompositor.self
        // The canvas's shape follows the style's aspect ratio (S-027).
        config.renderSize = renderSize ?? canvasSize(for: style.style)
        config.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.instructions = slots.map {
            BubbleInstruction(timeRange: $0.timeRange, screenTrack: $0.screenTrack, cameraTrack: $0.cameraTrack,
                              scene: scene, sourceOffset: $0.sourceOffset, style: style)
        }
        return AVVideoComposition(configuration: config)
    }

    /// The video's size before export scaling: the crop in the style's aspect ratio.
    func canvasSize(for style: Style) -> CGSize { CanvasLayout.canvasSize(for: style, source: naturalSize) }

    private static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60_000) }

    private static func insert(_ range: CMTimeRange, of source: Track, into track: AVMutableCompositionTrack?, at: CMTime) {
        let available = source.range.intersection(range)
        guard let track, !available.isEmpty else { return }
        try? track.insertTimeRange(available, of: source.track, at: at + (available.start - range.start))
    }
}
