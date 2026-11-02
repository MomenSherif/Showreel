import AppKit
import AVFoundation
import ImageIO
import ShowreelKit

/// Self-test checks for export (M6).
extension SelfTest {
    /// S-036: File > Export… exists, and the open project exports to an MP4
    /// and a GIF with the cut's length and the chosen size.
    static func export(_ editor: EditorModel) async {
        // SwiftUI nests command groups in untitled items; look through all of them.
        // and let each menu fill itself in, as it does when it opens.
        func items(_ menu: NSMenu?) -> [NSMenuItem] {
            guard let menu else { return [] }
            menu.delegate?.menuNeedsUpdate?(menu)
            return menu.items.flatMap { [$0] + items($0.submenu) }
        }
        let file = items(NSApp.mainMenu?.item(withTitle: "File")?.submenu)
        check("the File menu has the project commands",
              ["Duplicate", "Rename…", "Show in Finder", "Export…", "Move to Trash"].allSatisfy { t in file.contains { $0.title == t } },
              file.map(\.title).joined(separator: ", "))
        let item = file.first { $0.title == "Export…" }
        check("File > Export… has ⌘E", item?.keyEquivalent == "e" && item?.keyEquivalentModifierMask == .command,
              file.map { "\($0.title) [\($0.keyEquivalent)]" }.joined(separator: ", "))

        editor.showExportSheet()
        check("Export… opens the Export sheet", editor.showsExportSheet)
        editor.showsExportSheet = false

        let folder = URL(fileURLWithPath: "/tmp/Showreel-export-selftest", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let mp4 = folder.appending(path: "export.mp4")
        let settings = ExportSettings(format: .mp4, resolution: .p720, fps: 30, quality: .standard)
        let started = Date.now
        guard let run = editor.startExport(to: mp4, settings: settings) else {
            check("an MP4 export starts", false)
            return
        }
        check("a second export cannot start while one runs", editor.startExport(to: mp4, settings: settings) == nil && !editor.canExport)
        await run.finished()
        print(String(format: "INFO MP4 720p30 export of %.1f s took %.1f s", editor.duration, Date.now.timeIntervalSince(started)))
        check("the MP4 export finishes", run.state == .finished, "\(run.state)")
        let asset = AVURLAsset(url: mp4)
        let length = (try? await asset.load(.duration).seconds) ?? 0
        check("the MP4 is as long as the cut", abs(length - editor.duration) < 0.1, "\(length) s, cut \(editor.duration) s")
        let size = try? await asset.loadTracks(withMediaType: .video).first?.load(.naturalSize)
        check("the MP4 has the chosen size", size == settings.outputSize(canvas: editor.canvasSize), "\(String(describing: size))")
        let sound = (try? await asset.loadTracks(withMediaType: .audio).count) ?? 0
        check("the MP4 has sound when the project has", (sound > 0) == editor.hasAudio, "\(sound) audio tracks")
        check("the toolbar shows Export… again", editor.canExport)

        let gif = folder.appending(path: "export.gif")
        let gifRun = editor.startExport(to: gif, settings: ExportSettings(format: .gif, resolution: .p720, fps: 15))
        await gifRun?.finished()
        let frames = CGImageSourceCreateWithURL(gif as CFURL, nil).map(CGImageSourceGetCount) ?? 0
        let expected = Int((editor.duration * 15).rounded())
        check("the GIF has a frame for every 1/15 s", gifRun?.state == .finished && abs(frames - expected) <= 1,
              "\(frames) frames, \(expected) expected")
        editor.export = nil
    }
}
