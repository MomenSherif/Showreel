import AppKit
import SwiftData
import ShowreelKit

/// Self-test checks for Settings (S-045). The run has its own empty
/// settings (`Store.defaults`), so these start from the standard values.
extension SelfTest {
    static func settings(_ model: AppModel) async {
        let settings = AppSettings.shared
        check("Settings has the tabs General, Recording, Export, Captions, and Appearance",
              SettingsTab.allCases.map(\.title) == ["General", "Recording", "Export", "Captions", "Appearance"])
        check("the Record Shortcut starts as ⌃⌥⌘R and the Countdown as 3 seconds",
              settings.recordShortcut == .record && settings.countdownSeconds == 3)

        // The Record Shortcut.
        let plain = Shortcut(keyCode: 3, key: "f")
        check("a shortcut without ⌘, ⌥, or ⌃ is refused and the old one kept",
              settings.setRecordShortcut(plain) == .needsModifier && settings.recordShortcut == .record)
        let mine = Shortcut(keyCode: 3, key: "f", option: true, command: true)
        check("a new Record Shortcut is taken", settings.setRecordShortcut(mine) == nil && settings.recordShortcut == mine)
        check("the Record Shortcut is kept for the next launch",
              Shortcut.decode(Store.defaults.data(forKey: "record.shortcut")) == mine)
        try? await Task.sleep(for: .seconds(0.3))
        // As when the menu opens: SwiftUI fills a command menu then.
        if let menu = NSApp.mainMenu?.item(withTitle: "Record")?.submenu { menu.delegate?.menuNeedsUpdate?(menu) }
        let item = NSApp.mainMenu?.item(withTitle: "Record")?.submenu?.items.first
        check("the Record menu shows the new shortcut",
              item?.keyEquivalent == "f" && item?.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == [.option, .command],
              "\(item?.keyEquivalent ?? "-") \(item?.keyEquivalentModifierMask.rawValue ?? 0)")
        StatusItem.shared.update()
        let extra = StatusItem.shared.menu.items.first
        check("the menu bar menu shows the new shortcut", extra?.keyEquivalent == "f")
        settings.setRecordShortcut(.record)

        // The Exports folder: a chosen folder, and Movies when it is gone.
        let folder = URL(fileURLWithPath: "/tmp/Showreel-exports-selftest", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        settings.exportsFolder = folder
        check("the Exports folder is kept", settings.exportsFolder.standardizedFileURL.path == folder.path)
        try? FileManager.default.removeItem(at: folder)
        check("a missing Exports folder falls back to Movies", settings.exportsFolder == URL.moviesDirectory)

        // Export choices: Settings and the Export sheet share them.
        let saved = settings.exportSettings
        let choices = ExportSettings(format: .mov, resolution: .p2160, fps: 30, quality: .best)
        settings.exportSettings = choices
        check("the export choices are kept for the next launch",
              ExportSettings.decode(Store.defaults.data(forKey: "export.settings")) == choices)
        settings.exportSettings = saved

        // Style for New Recordings.
        var look = Style()
        look.padding = 0.2
        let preset = model.savePreset(named: "Self-test settings preset", style: look)
        model.makeDefault(preset)
        let project = model.addProject(title: "Self-test settings project")
        check("a new project starts with the Style for New Recordings", project.styleData == preset.styleData)
        model.makeDefault(nil)
        model.context.delete(project)
        model.deletePreset(preset)

        await countdownOff(model)
    }

    /// Countdown Off: recording starts with no Countdown shown.
    static func countdownOff(_ model: AppModel) async {
        guard CGPreflightScreenCaptureAccess() else { return }
        let recorder = RecordController.shared
        let settings = AppSettings.shared
        let saved = (recorder.micOn, recorder.cameraOn, recorder.systemAudioOn, recorder.sourceKind)
        let welcome = Store.defaults.object(forKey: "welcome.done")
        defer {
            settings.countdownSeconds = CountdownLength.standard
            recorder.micOn = saved.0; recorder.cameraOn = saved.1; recorder.systemAudioOn = saved.2; recorder.sourceKind = saved.3
            Store.defaults.set(welcome, forKey: "welcome.done")
        }
        settings.countdownSeconds = 0
        recorder.micOn = false
        recorder.cameraOn = false
        recorder.systemAudioOn = false
        recorder.sourceKind = .display
        Store.defaults.set(true, forKey: "welcome.done")
        let before = Set(all(model).map(\.uuid))
        recorder.newRecording()
        await recorder.loadContent()
        recorder.displayID = CGMainDisplayID()
        recorder.start()
        var sawCountdown = false
        for _ in 0..<60 where recorder.state != .recording {
            if Countdown.shared.window != nil { sawCountdown = true }
            try? await Task.sleep(for: .seconds(0.05))
        }
        check("with the Countdown Off, recording starts with no Countdown",
              recorder.state == .recording && !sawCountdown, "state \(recorder.state)")
        recorder.stop()
        for _ in 0..<40 where recorder.state != .idle { try? await Task.sleep(for: .seconds(0.25)) }
        for project in all(model) where !before.contains(project.uuid) {
            for window in NSApp.windows where window.title == project.title { window.close() }
            try? FileManager.default.removeItem(at: ProjectStore.folder(for: project.uuid))
            model.context.delete(project)
        }
        try? model.context.save()
    }
}
