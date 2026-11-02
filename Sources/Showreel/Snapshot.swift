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
/// APP_SNAPSHOT_PAGES=library,record-panel limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    /// A panel shown only for one snapshot.
    private static var standalone: NSWindow?

    static var isActive: Bool { !(ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty }

    /// One floating panel or extra window: how to show it, find it, and close it.
    private struct Surface {
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
        ] + editorSurfaces(model: model)
    }

    /// The Editor, once per inspector section: "editor" shows Background,
    /// "editor-<section>" the others.
    private static func editorSurfaces(model: AppModel) -> [Surface] {
        let title = SeedData.samples.first?.title
        let window = { NSApp.windows.first { $0.title == title && $0.isVisible } }
        /// Opens the first sample in the Editor if no snapshot page did yet.
        let openEditor: () async -> EditorModel? = {
            let project = (try? model.context.fetch(FetchDescriptor<Project>()))?.first { $0.title == title }
            if let project, window() == nil { AppServices.shared.openProject(project.uuid) }
            for _ in 0..<30 where EditorModel.newest?.player == nil { try? await Task.sleep(for: .seconds(0.1)) }
            return EditorModel.newest
        }
        let zoomed = Surface(name: "editor-zoomed", show: {
                                 let project = (try? model.context.fetch(FetchDescriptor<Project>()))?.first { $0.title == title }
                                 if let project, window() == nil { AppServices.shared.openProject(project.uuid) }
                                 for _ in 0..<20 where EditorModel.newest == nil { try? await Task.sleep(for: .seconds(0.1)) }
                                 EditorModel.newest?.section = .background
                                 EditorModel.newest?.seek(to: 12.3)
                                 EditorModel.newest?.zoom = TimelineZoom(level: 0.9)
                             },
                             window: window,
                             hide: { window()?.close() })
        // S-031: the zoom around 0:12 selected, the playhead inside it.
        let zoomSelected = Surface(name: "editor-zoom-selected", show: {
                                       guard let editor = await openEditor() else { return }
                                       editor.zoom = TimelineZoom()
                                       editor.section = .background
                                       let zoom = editor.zooms.segment(at: 12.6)
                                       editor.selectZoom(zoom?.id)
                                       editor.seek(to: 12.6)
                                       // The focus preview loads its frame.
                                       try? await Task.sleep(for: .seconds(0.5))
                                   },
                                   window: window,
                                   hide: { EditorModel.newest?.selectZoom(nil) })
        // S-018: the start being trimmed by 6 s, mid-drag.
        let trim = Surface(name: "editor-trim", show: {
                               let project = (try? model.context.fetch(FetchDescriptor<Project>()))?.first { $0.title == title }
                               if let project, window() == nil { AppServices.shared.openProject(project.uuid) }
                               for _ in 0..<20 where EditorModel.newest?.player == nil { try? await Task.sleep(for: .seconds(0.1)) }
                               guard let editor = EditorModel.newest, let first = editor.edits.segments.first else { return }
                               editor.zoom = TimelineZoom()
                               editor.section = .background
                               editor.selectedSegment = first.id
                               editor.previewTrim(first.id, edge: .start, by: 6)
                           },
                           window: window,
                           hide: {})
        // S-019: split twice, the middle piece selected.
        let split = Surface(name: "editor-split", show: {
                                guard let editor = await openEditor() else { return }
                                editor.section = .background
                                editor.selectedSegment = nil
                                editor.apply(EditList(sourceDuration: editor.edits.sourceDuration))
                                editor.seek(to: 12)
                                editor.splitAtPlayhead()
                                editor.seek(to: 24)
                                editor.splitAtPlayhead()
                                editor.selectedSegment = editor.edits.segments[1].id
                            },
                            window: window,
                            hide: {})
        // S-025: Crop Screen with a crop set, so the handles and dimming show.
        let crop = Surface(name: "crop-sheet", show: {
                               guard let editor = await openEditor() else { return }
                               var style = editor.style
                               style.crop = CropRect(x: 0.1, y: 0.12, width: 0.75, height: 0.7) // grid: ok normalized crop
                               editor.applyStyle(style, named: "Crop")
                               editor.showsCropSheet = true
                           },
                           window: { window()?.attachedSheet },
                           hide: {
                               guard let editor = EditorModel.newest else { return }
                               editor.showsCropSheet = false
                               var style = editor.style
                               style.crop = .full
                               editor.applyStyle(style, named: "Crop")
                           })
        // S-026: the Browser frame with an address, in Inspector > Screen.
        let frame = Surface(name: "editor-frame", show: {
                                guard let editor = await openEditor() else { return }
                                editor.section = .screen
                                var style = editor.style
                                style.frame = .browser
                                style.url = "showreel.app/pricing"
                                editor.applyStyle(style, named: "Frame")
                            },
                            window: window,
                            hide: {
                                guard let editor = EditorModel.newest else { return }
                                var style = editor.style
                                style.frame = .none
                                style.url = ""
                                editor.applyStyle(style, named: "Frame")
                            })
        // S-027: a 9:16 canvas, from Inspector > Background.
        let aspect = Surface(name: "editor-aspect", show: {
                                 guard let editor = await openEditor() else { return }
                                 editor.section = .background
                                 var style = editor.style
                                 style.aspect = .tall
                                 editor.applyStyle(style, named: "Aspect Ratio")
                             },
                             window: window,
                             hide: {
                                 guard let editor = EditorModel.newest else { return }
                                 var style = editor.style
                                 style.aspect = .auto
                                 editor.applyStyle(style, named: "Aspect Ratio")
                             })
        // S-029: Save Style as Preset.
        let savePreset = Surface(name: "save-preset", show: {
                                     guard let editor = await openEditor() else { return }
                                     editor.section = .background
                                     editor.showsSavePreset = true
                                 },
                                 window: { window()?.attachedSheet },
                                 hide: { EditorModel.newest?.showsSavePreset = false })
        return InspectorSection.allCases.map { section in
            Surface(name: section == .background ? "editor" : "editor-\(section.rawValue)", show: {
                        let project = (try? model.context.fetch(FetchDescriptor<Project>()))?.first { $0.title == title }
                        if let project, window() == nil { AppServices.shared.openProject(project.uuid) }
                        for _ in 0..<20 where EditorModel.newest == nil { try? await Task.sleep(for: .seconds(0.1)) }
                        EditorModel.newest?.section = section
                    },
                    window: window,
                    hide: {})
        } + [trim, split, crop, frame, aspect, savePreset, zoomSelected, zoomed]
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
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
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
