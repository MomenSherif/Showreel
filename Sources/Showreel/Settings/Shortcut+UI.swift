import AppKit
import SwiftUI
import ShowreelKit

extension Shortcut {
    /// The shortcut from a key press, as typed in Settings.
    init(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.init(keyCode: event.keyCode, key: event.charactersIgnoringModifiers ?? "",
                  control: flags.contains(.control), option: flags.contains(.option),
                  shift: flags.contains(.shift), command: flags.contains(.command))
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if control { flags.insert(.control) }
        if option { flags.insert(.option) }
        if shift { flags.insert(.shift) }
        if command { flags.insert(.command) }
        return flags
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var mods: SwiftUI.EventModifiers = []
        if control { mods.insert(.control) }
        if option { mods.insert(.option) }
        if shift { mods.insert(.shift) }
        if command { mods.insert(.command) }
        return mods
    }

    /// For a menu item: `.keyboardShortcut(shortcut.keyboardShortcut)`.
    var keyboardShortcut: KeyboardShortcut? {
        guard let character = key.first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: eventModifiers)
    }
}
