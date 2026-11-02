import AVFoundation
import CoreImage
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
    /// Crop Screen is open (S-025).
    var showsCropSheet = false
    /// Save Style as Preset is open (S-029).
    var showsSavePreset = false
    /// The timeline's zoom (S-017). Fit shows the whole recording.
    var zoom = TimelineZoom()
    /// The cut (S-018, S-019). Edits replace it; the files never change.
    private(set) var edits = EditList(sourceDuration: 0)
    /// A trim being dragged, shown on the timeline before it is applied.
    private(set) var draft: EditList?
    /// The selected clip segment on the timeline.
    var selectedSegment: EditList.Segment.ID?

    /// The look (M4): background, padding, and more. Changed through
    /// `applyStyle` (EditorModel+Style.swift), like the cut.
    var style = Style()
    /// The zooms (M5), in source time. Drawn without a rebuild, like the style.
    var zooms = ZoomTrack()

    @ObservationIgnored private(set) var sources: PlayerSources?
    /// The current item's segments, so a style change can redraw without a rebuild.
    @ObservationIgnored var slots: [PlayerSources.Slot] = []
    /// Background pictures, loaded once at the canvas size, by file path.
    @ObservationIgnored var pictures: [String: CIImage] = [:]

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var rateObserver: NSKeyValueObservation?

    /// The newest Editor, for snapshot mode and the self-test.
    private(set) static weak var newest: EditorModel?

    init(project: Project) {
        self.project = project
        duration = project.duration
    }

    /// Loads the tracks and the saved cut, and makes the player. Called once per window.
    func load() async {
        guard player == nil, let sources = await PlayerSources.load(for: project) else { return }
        self.sources = sources
        edits = EditList.decode(project.editsData, sourceDuration: sources.duration)
        style = Style.decode(project.styleData)
        zooms = Self.zooms(for: project, sources: sources)
        duration = edits.duration
        let built = sources.item(for: edits, style: renderStyle(for: style))
        slots = built.slots
        let player = AVPlayer(playerItem: built.item)
        player.actionAtItemEnd = .pause
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

    /// The saved zooms, or on the first open, zooms made from the clicks and
    /// typing in events.json, saved so they can be edited (S-030).
    static func zooms(for project: Project, sources: PlayerSources) -> ZoomTrack {
        if let saved = ZoomTrack.decode(project.zoomsData) { return saved }
        let made = ZoomTrack(segments: sources.events.map { AutoZoom.segments(from: $0, duration: sources.duration) } ?? [])
        project.zoomsData = made.encoded()
        try? project.modelContext?.save()
        return made
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

    // MARK: Edits (S-018, S-019)

    /// The window's undo manager. Every edit is one step on it (S-020).
    @ObservationIgnored weak var undoManager: UndoManager? {
        didSet { observeUndo() }
    }
    private(set) var canUndo = false
    private(set) var canRedo = false
    @ObservationIgnored private var undoObservers: [NSObjectProtocol] = []

    /// Replaces the cut, as one undoable step called `name` ("Undo Split").
    /// The playhead stays on the same moment of the recording when that
    /// moment is still in the video. Drags apply once, when they end, so a
    /// drag is one step.
    func apply(_ new: EditList, named name: String = "Edit") {
        guard new != edits, let sources, let player else { draft = nil; return }
        let old = edits
        undoManager?.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated { editor.apply(old, named: name) }
        }
        undoManager?.setActionName(name)
        let source = edits.sourceTime(atEditTime: playhead.time)
        edits = new
        draft = nil
        duration = new.duration
        project.editsData = new.encoded()
        // Saved right away (S-021): an edit is small and comes at most once
        // per action, and a crash must not lose it.
        try? project.modelContext?.save()
        if let selectedSegment, !new.segments.contains(where: { $0.id == selectedSegment }) { self.selectedSegment = nil }
        let wasPlaying = isPlaying
        let built = sources.item(for: new, style: renderStyle(for: style))
        slots = built.slots
        player.replaceCurrentItem(with: built.item)
        seek(to: source.flatMap { new.editTime(atSourceTime: $0) } ?? min(playhead.time, duration))
        if wasPlaying { player.play() }
        refreshUndo()
    }

    func observeUndo() {
        undoObservers.forEach(NotificationCenter.default.removeObserver)
        undoObservers = []
        guard let undoManager else { return }
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
                     .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerCheckpoint] {
            undoObservers.append(NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshUndo() }
            })
        }
        refreshUndo()
    }

    func refreshUndo() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }

    enum Edge { case start, end }

    /// Shows a trim while its edge is dragged: `delta` seconds from where
    /// the edge was in `edits`.
    func previewTrim(_ id: EditList.Segment.ID, edge: Edge, by delta: Double) {
        guard let segment = edits.segments.first(where: { $0.id == id }) else { return }
        var new = edits
        switch edge {
        case .start: new.trimStart(id, toSource: segment.start + delta)
        case .end: new.trimEnd(id, toSource: segment.end + delta)
        }
        draft = new
    }

    func commitTrim() {
        if let draft { apply(draft, named: "Trim") }
        draft = nil
    }

    /// Clip > Split at Playhead (S): two pieces where there was one (S-019).
    func splitAtPlayhead() {
        var new = edits
        guard new.split(atEditTime: playhead.time) != nil else { return }
        apply(new, named: "Split")
    }

    /// Clip > Delete Section (⌫): removes the selected piece and closes the gap.
    var canDeleteSelection: Bool { selectedSegment != nil && edits.segments.count > 1 }

    func deleteSelection() {
        guard let selectedSegment else { return }
        var new = edits
        guard new.delete(selectedSegment) else { return }
        self.selectedSegment = nil
        apply(new, named: "Delete Section")
    }

    /// Clip > Trim Start to Playhead (⌥[).
    func trimStartToPlayhead() {
        guard let (segment, _) = edits.segment(atEditTime: playhead.time),
              let s = edits.sourceTime(atEditTime: playhead.time) else { return }
        var new = edits
        new.trimStart(segment.id, toSource: s)
        apply(new, named: "Trim Start")
    }

    /// Clip > Trim End to Playhead (⌥]).
    func trimEndToPlayhead() {
        guard let (segment, _) = edits.segment(atEditTime: playhead.time),
              let s = edits.sourceTime(atEditTime: playhead.time) else { return }
        var new = edits
        new.trimEnd(segment.id, toSource: s)
        apply(new, named: "Trim End")
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
