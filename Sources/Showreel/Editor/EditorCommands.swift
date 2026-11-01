import AppKit
import SwiftUI

/// The Playback menu (docs/DESIGN.md, "Command map"). It acts on the Editor
/// in the key window.
struct PlaybackCommands: Commands {
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        CommandMenu("Playback") {
            // With no Editor in front, the keys keep their usual meaning.
            Group {
                Button(editor?.isPlaying == true ? "Pause" : "Play") { act(.space) { $0.togglePlay() } }
                    .keyboardShortcut(.space, modifiers: [])
                Divider()
                Button("Previous Frame") { act(.left) { $0.step(frames: -1) } }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Next Frame") { act(.right) { $0.step(frames: 1) } }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Back 1 Second") { act(.shiftLeft) { $0.jump(by: -1) } }
                    .keyboardShortcut(.leftArrow, modifiers: .shift)
                Button("Forward 1 Second") { act(.shiftRight) { $0.jump(by: 1) } }
                    .keyboardShortcut(.rightArrow, modifiers: .shift)
                Divider()
                Button("Go to Start") { act(.home) { $0.goToStart() } }
                    .keyboardShortcut(.home, modifiers: [])
                Button("Go to End") { act(.end) { $0.goToEnd() } }
                    .keyboardShortcut(.end, modifiers: [])
            }
            .disabled(editor?.player == nil)
        }
    }

    /// Runs `action` on the Editor, unless a text field is being edited:
    /// then the key goes to the text, because a menu shortcut with no ⌘
    /// would otherwise take Space and the arrows away from typing.
    private func act(_ key: TextKey, _ action: (EditorModel) -> Void) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable {
            key.send(to: text)
            return
        }
        guard let editor, editor.player != nil else { return }
        action(editor)
    }
}

/// The keys the Playback menu uses, as a text view would handle them.
enum TextKey {
    case space, left, right, shiftLeft, shiftRight, home, end

    @MainActor func send(to text: NSTextView) {
        switch self {
        case .space: text.insertText(" ", replacementRange: text.selectedRange())
        case .left: text.moveLeft(nil)
        case .right: text.moveRight(nil)
        case .shiftLeft: text.moveLeftAndModifySelection(nil)
        case .shiftRight: text.moveRightAndModifySelection(nil)
        case .home: text.moveToBeginningOfLine(nil)
        case .end: text.moveToEndOfLine(nil)
        }
    }
}
