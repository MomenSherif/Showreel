import Carbon.HIToolbox
import ShowreelKit

/// The shortcuts that work in any app: the Record Shortcut (⌃⌥⌘R unless
/// changed in Settings > Recording), ⌃⌥⌘P to pause, and ⌃⌥⌘C for the camera.
@MainActor
enum HotKeys {
    enum Action: UInt32 { case record = 1, pause = 2, camera = 3 }

    private static var refs: [Action: EventHotKeyRef] = [:]
    private static var installed = false
    private(set) static var failed: [Action] = []

    static func register() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let raw = id.id
            Task { @MainActor in HotKeys.fire(raw) }
            return noErr
        }, 1, &spec, nil, nil)

        let fixed = UInt32(controlKey | optionKey | cmdKey)
        let shortcuts: [(Action, UInt32, UInt32)] = [
            (.record, UInt32(AppSettings.shared.recordShortcut.keyCode), modifiers(AppSettings.shared.recordShortcut)),
            (.pause, UInt32(kVK_ANSI_P), fixed),
            (.camera, UInt32(kVK_ANSI_C), fixed),
        ]
        for (action, key, mods) in shortcuts where !add(action, key: key, modifiers: mods) {
            failed.append(action)
        }
    }

    /// Swaps the Record Shortcut. False when the system refuses the new one;
    /// the old one is then put back. Before `register()` (snapshots, the
    /// self-test) nothing is held, so any shortcut is taken as is.
    static func replaceRecord(with shortcut: Shortcut) -> Bool {
        guard installed else { return true }
        let old = AppSettings.shared.recordShortcut
        remove(.record)
        if add(.record, key: UInt32(shortcut.keyCode), modifiers: modifiers(shortcut)) {
            failed.removeAll { $0 == .record }
            return true
        }
        _ = add(.record, key: UInt32(old.keyCode), modifiers: modifiers(old))
        return false
    }

    /// Lets go of the Record Shortcut while Settings listens for a new one,
    /// so typing the old keys there does not start a recording.
    static func setRecordPaused(_ paused: Bool) {
        guard installed else { return }
        if paused {
            remove(.record)
        } else if refs[.record] == nil {
            let shortcut = AppSettings.shared.recordShortcut
            _ = add(.record, key: UInt32(shortcut.keyCode), modifiers: modifiers(shortcut))
        }
    }

    private static func add(_ action: Action, key: UInt32, modifiers: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5348_5257), id: action.rawValue) // 'SHRW'
        let status = RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[action] = ref
        return true
    }

    private static func remove(_ action: Action) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
    }

    private static func modifiers(_ shortcut: Shortcut) -> UInt32 {
        var mods = 0
        if shortcut.control { mods |= controlKey }
        if shortcut.option { mods |= optionKey }
        if shortcut.shift { mods |= shiftKey }
        if shortcut.command { mods |= cmdKey }
        return UInt32(mods)
    }

    private static func fire(_ raw: UInt32) {
        guard let action = Action(rawValue: raw) else { return }
        let recorder = RecordController.shared
        switch action {
        case .record: recorder.toggleFromShortcut()
        case .pause: recorder.togglePause()
        case .camera: recorder.toggleCameraHidden()
        }
    }
}
