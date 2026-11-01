import Carbon.HIToolbox

/// Global shortcuts. Carbon hotkeys need no permission, and the keys never
/// reach the app in front.
///   ⌃⌥⌘R  New Recording / Stop Recording
///   ⌃⌥⌘P  Pause / Resume
///   ⌃⌥⌘C  Hide / Show Camera Bubble
enum HotKeys {
    enum Action: UInt32 { case record = 1, pause = 2, camera = 3 }

    private static var refs: [EventHotKeyRef] = []
    /// Shortcuts another app already owns, for Settings to show.
    private(set) static var failed: [Action] = []

    static func register() {
        guard refs.isEmpty else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let raw = id.id
            Task { @MainActor in HotKeys.fire(raw) }
            return noErr
        }, 1, &spec, nil, nil)

        let mods = UInt32(controlKey | optionKey | cmdKey)
        for (action, key) in [(Action.record, kVK_ANSI_R), (.pause, kVK_ANSI_P), (.camera, kVK_ANSI_C)] {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5348_5257), id: action.rawValue) // 'SHRW'
            let status = RegisterEventHotKey(UInt32(key), mods, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) } else { failed.append(action) }
        }
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
