import AppKit
import IOKit.pwr_mgt
import SwiftData
import SwiftUI
import ShowreelKit

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/Showreel.app/Contents/MacOS/Showreel
/// writes <page>-light.png and <page>-dark.png for every library page and
/// every surface (welcome, record-panel, source-picker, area-selector,
/// countdown, recording-controls, editor, editor-<section>), and settings-<tab>-light.png and
/// settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// The editor's menus open: menu-edit, menu-view, menu-clip, menu-playback.
/// APP_SNAPSHOT_PAGES=library,record-panel limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    /// A panel shown only for one snapshot.
    private static var standalone: NSWindow?

    static var isActive: Bool { !(ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty }

    /// One floating panel or extra window: how to show it, find it, and close it.
    struct Surface {
        let name: String
        let show: () async -> Void
        let window: () -> NSWindow?
        let hide: () -> Void
    }

    private static func surfaces(model: AppModel) -> [Surface] {
        let recorder = RecordController.shared
        let mainDisplay = CGMainDisplayID()
        return [
            Surface(name: "welcome", show: { AppServices.shared.openWelcome() },
                    window: { NSApp.windows.first { $0.title == "Welcome to Showreel" && $0.isVisible } },
                    hide: { NSApp.windows.first { $0.title == "Welcome to Showreel" }?.close() }),
            Surface(name: "record-panel", show: {
                        recorder.snapshotState(.panel)
                        RecordPanel.shared.show(activate: true)
                        await recorder.loadContent()
                    },
                    window: { RecordPanel.shared.panel },
                    hide: { RecordPanel.shared.hide(); recorder.snapshotState(.idle) }),
            Surface(name: "source-picker", show: {
                        recorder.snapshotState(.panel)
                        recorder.sourceKind = .display
                        RecordPanel.shared.show(activate: true)
                        await recorder.loadContent()
                        recorder.showingSourcePicker = true
                    },
                    window: { NSApp.windows.first { $0.className.contains("Popover") && $0.isVisible } },
                    hide: {
                        recorder.showingSourcePicker = false
                        RecordPanel.shared.hide()
                        recorder.snapshotState(.idle)
                    }),
            Surface(name: "area-selector", show: {
                        recorder.snapshotState(.panel)
                        recorder.area = CGRect(x: 320, y: 220, width: 960, height: 600)
                        AreaSelector.shared.begin()
                    },
                    window: { AreaSelector.shared.mainPanel },
                    hide: { AreaSelector.shared.hideOverlay(); recorder.area = nil; recorder.snapshotState(.idle) }),
            Surface(name: "camera-bubble", show: { CameraBubble.shared.show(session: nil, near: nil) },
                    window: { CameraBubble.shared.panel },
                    hide: { CameraBubble.shared.hide() }),
            // A child window captures as its parent, so the controls get a panel of their own here.
            Surface(name: "camera-bubble-controls", show: {
                        var options = FloatingPanel.Options()
                        options.takesKey = false
                        let panel = FloatingPanel(size: Layout.bubbleControls, options: options, content: BubbleControlsView())
                        panel.center()
                        panel.present()
                        standalone = panel
                    },
                    window: { standalone },
                    hide: { standalone?.orderOut(nil); standalone = nil }),
            Surface(name: "countdown", show: {
                        recorder.snapshotState(.countdown, countdown: 3)
                        Countdown.shared.show(on: mainDisplay)
                    },
                    window: { Countdown.shared.window },
                    hide: { Countdown.shared.hide(); recorder.snapshotState(.idle) }),
            Surface(name: "recording-controls", show: {
                        recorder.snapshotState(.recording, elapsed: 72)
                        RecordingControls.shared.show(on: mainDisplay)
                    },
                    window: { RecordingControls.shared.panel },
                    hide: { RecordingControls.shared.hide(); recorder.snapshotState(.idle) }),
            // S-046: the standard About panel, with the app icon.
            // AppKit's About panel is a plain NSPanel with no title.
            Surface(name: "about", show: { NSApp.orderFrontStandardAboutPanel(nil) },
                    window: { aboutPanel },
                    hide: { aboutPanel?.close() }),
        ] + editorSurfaces(model: model)
    }

    private static var aboutPanel: NSWindow? {
        NSApp.windows.first { $0.isVisible && type(of: $0) == NSPanel.self && $0.title.isEmpty }
    }

    /// Speech models as a person with Handy would have them, whatever this
    /// Mac holds: Whisper Small from Handy, Turbo not downloaded (S-051).
    /// Sparse files of the exact size, so nothing is written.
    static func fakeSpeechModels() {
        let root = URL(fileURLWithPath: "/tmp/Showreel-snapshot-models")
        let handy = root.appending(path: "handy")
        try? FileManager.default.createDirectory(at: handy, withIntermediateDirectories: true)
        let small = handy.appending(path: SpeechModel.whisperSmall.fileName ?? "")
        if !FileManager.default.fileExists(atPath: small.path) {
            FileManager.default.createFile(atPath: small.path, contents: nil)
            if let handle = try? FileHandle(forWritingTo: small) {
                try? handle.truncate(atOffset: UInt64(SpeechModel.whisperSmall.byteCount ?? 0))
                try? handle.close()
            }
        }
        SpeechModels.shared.locator = ModelLocator(own: root.appending(path: "own"), handy: handy)
    }

    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real database.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        fakeSpeechModels()
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in LibraryPage.allCases where only?.contains(page.rawValue) ?? true {
                    model.page = page
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
            }
            for surface in surfaces(model: model) where only?.contains(surface.name) ?? true {
                model.page = .library
                await surface.show()
                try? await Task.sleep(for: .seconds(1.5))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    if let window = surface.window() {
                        capture(to: "\(dir)/\(surface.name)-\(mode).png", window: window)
                    } else {
                        print("SNAPSHOT no window for \(surface.name)")
                    }
                }
                surface.hide()
                try? await Task.sleep(for: .seconds(0.3))
            }
            await captureMenus(model: model, dir: dir, only: only)
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        // SwiftUI's Settings window by its identifier: an editor or the
                        // Record Panel can still be open from an earlier page.
                        let settings = NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true && $0.isVisible }
                            ?? NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && !($0 is NSPanel) }
                        if settings == nil { print("SNAPSHOT no Settings window for \(tab.rawValue)") }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
