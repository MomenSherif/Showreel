import AppKit
import ShowreelKit

/// The menu bar extra (S-002). Idle: New Recording, Open Library, recent
/// projects, Settings…, Quit Showreel. Recording: a red dot with the time,
/// and Stop and Pause at the top (docs/DESIGN.md, "Command map").
final class StatusItem: NSObject, NSMenuDelegate {
    static let shared = StatusItem()

    private var item: NSStatusItem?
    private var timer: Timer?
    /// The menu as last built, for the self-test.
    private(set) var menu = NSMenu()

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Showreel: New Recording (⌃⌥⌘R)"
        menu.delegate = self
        item.menu = menu
        self.item = item
        update()
    }

    /// Redraws the icon and title; called when the recording state changes.
    func update() {
        let recorder = RecordController.shared
        guard let button = item?.button else { rebuild(); return }
        if recorder.isCapturing {
            let image = NSImage(systemSymbolName: recorder.state == .paused ? "pause.circle.fill" : "record.circle.fill",
                                accessibilityDescription: "Recording")
            let config = NSImage.SymbolConfiguration(paletteColors: [.white, .systemRed])
            button.image = image?.withSymbolConfiguration(config)
            button.title = " " + TimeText.clock(recorder.elapsed)
            button.imagePosition = .imageLeading
            startTicking()
        } else {
            button.image = NSImage(systemSymbolName: "rectangle.inset.filled.and.person.filled", accessibilityDescription: "Showreel")
            button.title = ""
            timer?.invalidate()
            timer = nil
        }
        rebuild()
    }

    private func startTicking() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let recorder = RecordController.shared
                StatusItem.shared.item?.button?.title = " " + TimeText.clock(recorder.elapsed)
            }
        }
        timer?.tolerance = 0.1
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
        menu.removeAllItems()
        let recorder = RecordController.shared
        if recorder.isCapturing {
            add("Stop Recording \(TimeText.clock(recorder.elapsed))", key: "r", #selector(stop))
            add(recorder.state == .paused ? "Resume Recording" : "Pause Recording", key: "p", #selector(pause))
        } else {
            add("New Recording", key: "r", #selector(newRecording))
        }
        add("Open Library", key: "", #selector(openLibrary))
        let recent = AppServices.shared.recentProjects(limit: 3)
        if !recent.isEmpty {
            menu.addItem(.separator())
            for project in recent {
                let item = NSMenuItem(title: project.title, action: #selector(openProject(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = project.uuid
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        add("Settings…", key: ",", #selector(openSettings), global: false)
        add("Quit Showreel", key: "q", #selector(quit), global: false)
    }

    private func add(_ title: String, key: String, _ action: Selector, global: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = global ? [.control, .option, .command] : [.command]
        item.target = self
        menu.addItem(item)
    }

    @objc private func newRecording() { RecordController.shared.newRecording() }
    @objc private func stop() { RecordController.shared.stop() }
    @objc private func pause() { RecordController.shared.togglePause() }
    @objc private func openLibrary() { AppServices.shared.openLibrary() }
    @objc private func openSettings() { AppServices.shared.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openProject(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        AppServices.shared.openProject(id)
    }

    var itemTitles: [String] { menu.items.map(\.title) }
}
