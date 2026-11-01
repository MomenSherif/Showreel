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
        guard old != new else { return }
        undoManager?.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated { editor.applyStyle(old, named: name) }
        }
        undoManager?.setActionName(name)
        let changed = style != new
        style = new
        project.styleData = new.encoded()
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
        guard let url else { return RenderStyle(style: style) }
        if pictures[url.path] == nil, let sources {
            pictures[url.path] = Self.picture(at: url, maxPixels: max(sources.naturalSize.width, sources.naturalSize.height))
        }
        return RenderStyle(style: style, backgroundImage: pictures[url.path])
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

    /// The recording's frame under the playhead, uncropped, for Crop Screen.
    func currentSourceFrame() async -> CGImage? {
        guard let sources, let time = edits.sourceTime(atEditTime: playhead.time) else { return nil }
        let generator = AVAssetImageGenerator(asset: sources.screen.asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        return try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
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
