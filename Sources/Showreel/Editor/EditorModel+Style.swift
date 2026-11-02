import AppKit
import AVFoundation
import CoreImage
import ImageIO
import ShowreelEngine
import ShowreelKit

/// Style changes (M4): the same undo and save path as the cut.
extension EditorModel {
    /// Replaces the style as one undoable step called `name`, and saves it.
    func applyStyle(_ new: Style, named name: String) {
        commitStyle(from: style, to: new, named: name)
    }

    /// Shows `new` on the canvas without an undo step or a save: for a
    /// slider while it is dragged. `commitStyle(from:named:)` ends the drag.
    func previewStyle(_ new: Style) {
        guard new != style else { return }
        style = new
        redraw()
    }

    /// Ends a drag that started at `old`: one undo step for the whole drag.
    func commitStyle(from old: Style, named name: String) {
        commitStyle(from: old, to: style, named: name)
    }

    private func commitStyle(from old: Style, to new: Style, named name: String) {
        commitDrawn(from: old, to: new, named: name, current: { $0.style }) { editor, style in
            editor.style = style
            editor.project.styleData = style.encoded()
        }
    }

    /// The one undo, save, and redraw path for edits that only change how
    /// frames are drawn (the style, the zooms): one undo step from `old` to
    /// `new`. `set` puts a value in place and writes it to the project;
    /// `current` reads it back for undo. After a drag's previews the value is
    /// already `new`, so only the save and the undo step remain.
    func commitDrawn<Value: Equatable & Sendable>(from old: Value, to new: Value, named name: String,
                                                  current: @escaping @Sendable @MainActor (EditorModel) -> Value,
                                                  set: @escaping @Sendable @MainActor (EditorModel, Value) -> Void) {
        guard old != new else { return }
        undoManager?.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated {
                editor.commitDrawn(from: current(editor), to: old, named: name, current: current, set: set)
            }
        }
        undoManager?.setActionName(name)
        let changed = current(self) != new
        set(self, new)
        try? project.modelContext?.save()
        if changed { redraw() }
        refreshUndo()
    }

    /// Swaps the drawing on the current item; a paused frame is drawn again.
    func redraw() {
        guard let sources, let item = player?.currentItem else { return }
        item.videoComposition = sources.videoComposition(slots: slots, style: renderStyle(for: style))
        if !isPlaying { seek(to: playhead.time) }
    }

    /// The style with its background picture loaded.
    func renderStyle(for style: Style) -> RenderStyle {
        let url: URL? = switch style.background {
        case .wallpaper(let path): URL(fileURLWithPath: path)
        case .image(let name): ProjectStore.file(name, of: project.uuid)
        case .none, .gradient, .color: nil
        }
        let path = zoomPath(for: style), cursor = cursorScene(for: style)
        guard let url else { return RenderStyle(style: style, zooms: zooms, zoomPath: path, cursor: cursor) }
        if pictures[url.path] == nil, let sources {
            pictures[url.path] = Self.picture(at: url, maxPixels: max(sources.naturalSize.width, sources.naturalSize.height))
        }
        return RenderStyle(style: style, backgroundImage: pictures[url.path], zooms: zooms, zoomPath: path, cursor: cursor)
    }

    /// The cursor drawn from events.json (S-034); nil without a log.
    func cursorScene(for style: Style) -> CursorScene? {
        guard let sources, let log = sources.events else { return nil }
        let track: CursorTrack
        if let cache = cursorTrackCache, cache.smoothing == style.cursorSmoothing, cache.hides == style.cursorHidesWhenIdle {
            track = cache.track
        } else {
            track = CursorTrack(log: log, duration: sources.duration, smoothing: style.cursorSmoothing,
                                hidesWhenIdle: style.cursorHidesWhenIdle)
            cursorTrackCache = (style.cursorSmoothing, style.cursorHidesWhenIdle, track)
        }
        let pixelsPerPoint = log.source.width > 0 ? sources.naturalSize.width / log.source.width : 2
        return CursorScene(track: track, sprites: CursorSprites.system, pixelsPerPoint: pixelsPerPoint, scale: style.cursorScale,
                           clicks: clickMarks(log))
    }

    /// The clicks of `log`, built once per window.
    private func clickMarks(_ log: EventLog) -> ClickMarks {
        if let clickMarksCache { return clickMarksCache }
        let marks = ClickMarks(log.clicks)
        clickMarksCache = marks
        return marks
    }

    /// A picture decoded once at about the canvas size, so frames never
    /// decode a 6K wallpaper again.
    nonisolated static func picture(at url: URL, maxPixels: CGFloat) -> CIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 64),
              ] as CFDictionary) else { return nil }
        return CIImage(cgImage: image)
    }

    /// Where things are on the preview, in the canvas view's points
    /// (top-left origin), for handles drawn over it (S-028). `inset` is the
    /// canvas's margin around the video.
    struct CanvasGeometry {
        /// The whole video frame.
        let video: CGRect
        /// The recording inside it, after padding and the frame's chrome.
        let screen: CGRect
    }

    func canvasGeometry(in view: CGSize, inset: CGFloat) -> CanvasGeometry? {
        guard let sources else { return nil }
        let canvas = CanvasLayout.canvasSize(for: style, source: sources.naturalSize)
        let room = CGRect(origin: .zero, size: view).insetBy(dx: inset, dy: inset)
        guard canvas.width > 0, canvas.height > 0, room.width > 0, room.height > 0 else { return nil }
        let scale = min(room.width / canvas.width, room.height / canvas.height)
        let video = CGRect(x: room.midX - canvas.width * scale / 2, y: room.midY - canvas.height * scale / 2,
                           width: canvas.width * scale, height: canvas.height * scale)
        let content = style.crop.pixels(of: sources.naturalSize).size
        let chrome = CanvasLayout.chrome(for: style, canvasHeight: canvas.height)
        let screen = CanvasLayout.screenRect(content: content, canvas: canvas, padding: style.padding, chrome: chrome)
        return CanvasGeometry(video: video, screen: CGRect(x: video.minX + screen.minX * scale, y: video.minY + screen.minY * scale,
                                                           width: screen.width * scale, height: screen.height * scale))
    }

    /// The camera's center now, normalized to the recording: the dragged
    /// position, or the recorded path at the playhead.
    func cameraCenter(at editTime: Double) -> CGPoint? {
        guard let sources else { return nil }
        if let p = style.cameraPosition { return CGPoint(x: p.x, y: p.y) }
        let source = edits.sourceTime(atEditTime: editTime) ?? 0
        return style.crop.mapClamped(sources.scene.center(at: source))
    }

    /// The camera's diameter as a share of the recording's width.
    var cameraDiameter: CGFloat {
        (sources?.scene.diameter ?? 0) * CGFloat(min(max(style.cameraScale, 0.5), 2))
    }

    /// The recording's frame under the playhead, uncropped, for Crop Screen.
    func currentSourceFrame() async -> CGImage? {
        guard let time = edits.sourceTime(atEditTime: playhead.time) else { return nil }
        return await sourceFrame(at: time)
    }

    /// Copies the person's image into the project folder, so the project
    /// keeps working if the original moves, and makes it the background.
    func chooseBackgroundImage(_ url: URL) {
        let name = "background-\(UUID().uuidString.prefix(8)).\(url.pathExtension.lowercased())"
        let target = ProjectStore.file(name, of: project.uuid)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { return }
        var new = style
        new.background = .image(name)
        applyStyle(new, named: "Background Image")
    }
}

/// macOS wallpapers that are on this Mac at full size (S-022).
struct Wallpaper: Identifiable, Hashable {
    let name: String
    let url: URL
    var id: String { url.path }

    /// The current desktop pictures first, then the full-size system wallpapers.
    static func available() -> [Wallpaper] {
        var urls: [URL] = NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        let fm = FileManager.default
        let system = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.wallpapers")
        for folder in (try? fm.contentsOfDirectory(at: system, includingPropertiesForKeys: nil)) ?? [] {
            urls += ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "heic" && !$0.lastPathComponent.contains("Thumbnail") }
        }
        let downloaded = fm.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/com.apple.mobileAssetDesktop")
        urls += ((try? fm.contentsOfDirectory(at: downloaded, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "heic" }
        let images = Set(["heic", "jpg", "jpeg", "png", "tiff"])
        var seen = Set<String>()
        return urls.filter { images.contains($0.pathExtension.lowercased()) && seen.insert($0.standardizedFileURL.path).inserted }
            .map { Wallpaper(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
    }
}
