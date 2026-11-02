import AppKit
import SwiftData
import SwiftUI

// Showreel
//   Showreel                      the app
//   APP_STORE=<file> Showreel     use another database (tests, experiments); projects go to /tmp/Showreel-projects
//   APP_SNAPSHOT=<dir> Showreel   save a PNG of every page, panel, and Settings tab in light and dark mode, then quit
//   APP_SEED=1 Showreel           fill an empty /tmp store with sample projects (tools/snap.sh)
//   Showreel --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Showreel      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 Showreel           draw the 8 pt grid and the layout probes over the window

@main
struct ShowreelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let model = AppModel(container: Store.makeContainer())
        _model = State(initialValue: model)
        AppServices.shared.model = model
    }

    var body: some Scene {
        Window("Library", id: "library") {
            LibraryView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 560, minHeight: 400)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1000, height: 680)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.presented)
        .commands { ShowreelCommands(model: model) }

        WindowGroup("Project", id: "editor", for: UUID.self) { $id in
            if let id {
                EditorWindow(id: id)
                    .environment(model)
                    .themed()
            }
        }
        .modelContainer(model.container)
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)

        Window("Welcome to Showreel", id: "welcome") {
            WelcomeView()
                .themed()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

/// Every command in the menu bar (docs/DESIGN.md, "Command map").
struct ShowreelCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Commands exist from launch, with or without a window, so this is
        // where AppKit callers get their way to open windows.
        let _ = AppServices.shared.adopt(openWindow: openWindow)
        ToolbarCommands()
        InspectorCommands()
        EditorCommands()
        CommandGroup(replacing: .newItem) {
            Button("New Recording") { RecordController.shared.newRecording() }
                .keyboardShortcut("n")
            Button("Open") { open() }
                .keyboardShortcut("o")
                .disabled(selected == nil || selected?.isSaving == true)
        }
        // Not `after: .saveItem`: an app with no document group has no Save
        // group, and SwiftUI silently drops what is placed after it.
        CommandGroup(after: .newItem) {
            Divider()
            // Duplicate, Rename, and Move to Trash act on the Library's
            // selection, so they are off while an editor is in front (S-044).
            Button("Duplicate") { if let p = selected { ProjectStore.duplicate(p, in: model, undo: AppServices.shared.undoManager) } }
                .keyboardShortcut("d")
                .disabled(libraryTarget == nil || selected?.isSaving == true)
            Button("Rename…") { model.renaming = model.selection }
                .disabled(libraryTarget == nil)
            Button("Show in Finder") { if let p = editor?.project ?? selected { ProjectStore.showInFinder(p) } }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(editor == nil && selected == nil)
            Button("Export…") { export() }
                .keyboardShortcut("e")
                .disabled(exportDisabled)
            Divider()
            Button("Move to Trash") { if let p = selected { ProjectStore.moveToTrash(p, in: model, undo: AppServices.shared.undoManager) } }
                .keyboardShortcut(.delete)
                .disabled(libraryTarget == nil)
        }
        CommandMenu("Record") {
            RecordMenu()
        }
        CommandGroup(before: .windowList) {
            Button("Library") { openWindow(id: "library") }
                .keyboardShortcut("0")
            Divider()
        }
        CommandGroup(after: .help) {
            Button("Check Access…") { openWindow(id: "welcome") }
        }
    }

    private var selected: Project? { model.selectedProject }
    /// The Library's selection, when no editor is in front.
    private var libraryTarget: Project? { editor == nil ? selected : nil }
    @FocusedValue(\.editor) private var editor

    /// The front editor's project, or the Library's selection (S-036).
    private func export() {
        if let editor { editor.showExportSheet() } else if let p = selected { AppServices.shared.exportProject(p.uuid) }
    }

    private var exportDisabled: Bool {
        if let editor { return !editor.canExport }
        return selected == nil || selected?.isSaving == true
    }

    private func open() {
        guard let id = model.selection else { return }
        openWindow(id: "editor", value: id)
    }
}

/// The Record menu. Its labels follow the recording state.
private struct RecordMenu: View {
    private var recorder = RecordController.shared

    var body: some View {
        Button(recorder.isCapturing ? "Stop Recording" : "Start Recording") { recorder.toggleFromShortcut() }
            .keyboardShortcut("r", modifiers: [.control, .option, .command])
            .disabled(recorder.state == .saving)
        Button(recorder.state == .paused ? "Resume Recording" : "Pause Recording") { recorder.togglePause() }
            .keyboardShortcut("p", modifiers: [.control, .option, .command])
            .disabled(!recorder.isCapturing)
        Button("Restart Recording") { recorder.restart() }
            .disabled(!recorder.isCapturing)
        Divider()
        Button(recorder.cameraHidden ? "Show Camera Bubble" : "Hide Camera Bubble") { recorder.toggleCameraHidden() }
            .keyboardShortcut("c", modifiers: [.control, .option, .command])
            .disabled(!recorder.cameraOn)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // SwiftUI sometimes opens no window at launch (docs/FIXLOG.md).
        // The Library runs the seed data, self-test, and snapshots, so make sure it opens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { AppServices.shared.openLibrary() }
        }
        guard !SelfTest.requested, !Snapshot.isActive else { return }
        StatusItem.shared.install()
        HotKeys.register()
    }

    /// Showreel keeps running in the menu bar with no windows open.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { AppServices.shared.openLibrary() }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Recording", action: #selector(newRecording), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Library", action: #selector(openLibrary), keyEquivalent: "").target = self
        return menu
    }

    @objc private func newRecording() { RecordController.shared.newRecording() }
    @objc private func openLibrary() { AppServices.shared.openLibrary() }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/Showreel/Showreel.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "Showreel", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "Showreel.store")
    }

    /// The app's settings. Test, snapshot, and self-test runs get an empty
    /// domain of their own each launch, so they start from the defaults and
    /// never change the person's real settings.
    static let defaults: UserDefaults = {
        guard isOverridden else { return .standard }
        let name = "com.momensherif.showreel.testrun"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }()

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Project.self, StylePreset.self, configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}
