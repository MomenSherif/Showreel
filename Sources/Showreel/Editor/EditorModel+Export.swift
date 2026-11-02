import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers
import ShowreelEngine
import ShowreelKit

/// One export (S-036): where it goes, how far it is, and how it ended.
@Observable
final class ExportRun {
    enum State: Equatable {
        case running
        case finished
        case failed(String)
        case cancelled
    }

    let url: URL
    let projectID: UUID
    let settings: ExportSettings
    let size: CGSize
    let started: Date
    private(set) var fraction = 0.0
    private(set) var state = State.running
    /// The finished file's size (S-038).
    private(set) var fileBytes: Int64?
    @ObservationIgnored fileprivate var task: Task<Void, Never>?

    init(url: URL, projectID: UUID, settings: ExportSettings, size: CGSize, started: Date = .now) {
        self.started = started
        self.url = url
        self.projectID = projectID
        self.settings = settings
        self.size = size
    }

    var isRunning: Bool { state == .running }

    /// A run that only shows a state, for snapshot mode: `fraction` done
    /// after `elapsed` seconds, still running or finished.
    static func shown(for editor: EditorModel, fraction: Double, elapsed: Double, state: State = .running,
                      bytes: Int64? = nil) -> ExportRun {
        let settings = editor.savedExportSettings
        let run = ExportRun(url: URL(fileURLWithPath: "/tmp/\(editor.project.title).\(settings.format.fileExtension)"),
                            projectID: editor.project.uuid, settings: settings,
                            size: settings.outputSize(canvas: editor.canvasSize), started: .now - elapsed)
        run.fraction = fraction
        run.state = state
        run.fileBytes = bytes
        return run
    }

    /// Stops the export; the engine deletes the partial file.
    func cancel() {
        guard isRunning else { return }
        task?.cancel()
    }

    /// Waits until the export ends. For the self-test.
    func finished() async { await task?.value }

    fileprivate func report(_ fraction: Double) {
        // Progress comes ~60 times a second; redraw only on whole percents.
        guard isRunning, (fraction * 100).rounded(.down) != (self.fraction * 100).rounded(.down) else { return }
        self.fraction = fraction
    }

    fileprivate func end(_ state: State) {
        self.state = state
        guard state == .finished else { return }
        fraction = 1
        fileBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    /// Show in Finder (S-038).
    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Copy (S-038): the file itself, to paste into a chat or a Finder window.
    func copy(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }
}

extension EditorModel {
    static let exportSettingsKey = "export.settings"

    /// The last export's choices, or the defaults.
    var savedExportSettings: ExportSettings {
        ExportSettings.decode(Store.defaults.data(forKey: Self.exportSettingsKey))
    }

    /// The video's size before export scaling, for the size estimate.
    var canvasSize: CGSize { sources?.canvasSize(for: style) ?? .zero }

    /// True when the project has a mic or system audio track.
    var hasAudio: Bool { !(sources?.audio.isEmpty ?? true) }

    /// File > Export… (⌘E): opens the Export sheet, unless an export runs.
    var canExport: Bool { sources != nil && export?.isRunning != true }

    func showExportSheet() {
        guard canExport else { return }
        showsExportSheet = true
    }

    /// The Export sheet's Export… button: remembers the choices, then asks
    /// where to save with the system save panel (a sheet on `window`), and
    /// starts the export there.
    func chooseExportFile(settings: ExportSettings, window: NSWindow?) {
        Store.defaults.set(settings.encoded(), forKey: Self.exportSettingsKey)
        let panel = NSSavePanel()
        panel.title = "Export"
        panel.nameFieldStringValue = "\(project.title).\(settings.format.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: settings.format.fileExtension) ?? .movie]
        panel.canCreateDirectories = true
        if panel.directoryURL == nil {
            panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        }
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.startExport(to: url, settings: settings)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: done) } else { done(panel.runModal()) }
    }

    /// Renders the current cut, style, and zooms to `url`. Edits made while
    /// it runs are not in this export.
    @discardableResult
    func startExport(to url: URL, settings: ExportSettings) -> ExportRun? {
        guard let sources, export?.isRunning != true else { return nil }
        let settings = settings.fitted()
        let size = settings.outputSize(canvas: sources.canvasSize(for: style))
        let (composition, slots) = sources.composition(for: edits)
        let video = sources.videoComposition(slots: slots, style: renderStyle(for: style), renderSize: size, fps: settings.fps)
        // An immutable copy, which AVFoundation documents as safe to read
        // from any thread: the reader works on it off the main thread.
        nonisolated(unsafe) let asset = composition.copy() as! AVComposition
        let run = ExportRun(url: url, projectID: project.uuid, settings: settings, size: size)
        export = run
        // The popover opens by itself, so the export is seen to start (S-037).
        showsExportPopover = true
        run.task = Task { [weak run, weak self] in
            do {
                try await Exporter.export(asset: asset, videoComposition: video, settings: settings, to: url) { fraction in
                    Task { @MainActor in run?.report(fraction) }
                }
                run?.end(.finished)
                // The popover opens by itself to say it is done (S-038).
                self?.showsExportPopover = true
            } catch is CancellationError {
                run?.end(.cancelled)
                self?.showsExportPopover = false
            } catch {
                run?.end(.failed(error.localizedDescription))
            }
        }
        return run
    }
}
