import AppKit
import SwiftUI
import ShowreelKit

/// The Editor's menus (docs/DESIGN.md, "Command map"): the timeline zoom
/// in View, and the Playback menu. They act on the Editor in the key window.
struct EditorCommands: Commands {
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Group {
                Button("Zoom In") { act(nil) { $0.zoom.zoomIn() } }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(editor?.zoom.level == 1)
                Button("Zoom Out") { act(nil) { $0.zoom.zoomOut() } }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(editor?.zoom.level == 0)
                Button("Zoom to Fit") { act(.text("Z")) { $0.zoom.fit() } }
                    .keyboardShortcut("z", modifiers: .shift)
                    .disabled(editor?.zoom.isFit == true)
                Divider()
                // S-044: the inspector's sections, ⌘1 to ⌘6, beside ⌘0 for the Library.
                ForEach(Array(InspectorSection.allCases.enumerated()), id: \.element) { index, section in
                    Toggle(section.title, isOn: Binding(get: { editor?.section == section },
                                                        set: { _ in act(nil) { $0.showSection(section) } }))
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
            .disabled(editor == nil)
        }
        CommandMenu("Clip") {
            Group {
                Button("Split at Playhead") { act(.text("s")) { $0.splitAtPlayhead() } }
                    .keyboardShortcut("s", modifiers: [])
                Button("Add Zoom") { act(.text("z")) { $0.addZoom(atEditTime: $0.playhead.time) } }
                    .keyboardShortcut("z", modifiers: [])
                Button("Add Blur") { act(.text("b")) { $0.addBlur(atEditTime: $0.playhead.time) } }
                    .keyboardShortcut("b", modifiers: [])
                Button(editor?.isSelectionMuted == true ? "Unmute Section" : "Mute Section") {
                    act(.text("m")) { $0.toggleMuteSelection() }
                }
                .keyboardShortcut("m", modifiers: [])
                .disabled(editor?.canMuteSelection != true)
                Button("Unmute All") { act(.text("M")) { $0.unmuteAll() } }
                    .keyboardShortcut("m", modifiers: .shift)
                    .disabled(editor?.audio.muted.isEmpty != false)
                Toggle("Reduce Noise", isOn: Binding(get: { editor?.audio.reducesNoise == true },
                                                     set: { on in act(nil) { $0.setReducesNoise(on) } }))
                    .keyboardShortcut("n", modifiers: [.option, .command])
                    .disabled(editor?.project.hasMicrophone != true || editor?.noiseJob?.isRunning == true)
                Divider()
                Button("Generate Captions") { act(nil) { $0.generateCaptions() } }
                    .keyboardShortcut("g", modifiers: [.option, .command])
                    .disabled(editor?.canGenerateCaptions != true)
                Button("Edit Caption") { act(.newline) { $0.selectCaption($0.selectedCaption, editText: true) } }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(editor?.selectedCaption == nil)
                Toggle("Show Captions", isOn: styleBinding(\.captions.isVisible, named: "Show Captions"))
                    .keyboardShortcut("c", modifiers: [.shift, .command])
                    .disabled(editor?.captions.captions.isEmpty != false)
                Button("Save Caption Style…") {
                    act(nil) { editor in
                        editor.section = .captions
                        editor.savesCaptionStyle = true
                    }
                }
                .keyboardShortcut("s", modifiers: [.option, .shift, .command])
                .disabled(editor?.captions.captions.isEmpty != false)
                Toggle("Show Camera", isOn: styleBinding(\.cameraVisible, named: "Show Camera"))
                    .keyboardShortcut("k", modifiers: [.option, .command])
                    .disabled(editor?.project.hasCamera != true)
                Button(deleteTitle) {
                    act(.deleteBackward) { editor in
                        if editor.selectedCaption != nil {
                            editor.deleteSelectedCaption()
                        } else if editor.selectedZoom != nil {
                            editor.deleteSelectedZoom()
                        } else if editor.selectedBlur != nil {
                            editor.deleteSelectedBlur()
                        } else {
                            editor.deleteSelection()
                        }
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(editor?.selectedCaption == nil && editor?.selectedZoom == nil && editor?.selectedBlur == nil
                           && editor?.canDeleteSelection != true)
                Divider()
                if let editor {
                    Picker("Aspect Ratio", selection: aspectBinding(editor)) {
                        ForEach(Style.Aspect.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Frame", selection: Binding(get: { editor.style.frame }, set: { editor.setFrame($0) })) {
                        Text("None").tag(Style.DeviceFrame.none)
                        Text("Border").tag(Style.DeviceFrame.border)
                        Text("Browser").tag(Style.DeviceFrame.browser)
                        Text("MacBook").tag(Style.DeviceFrame.macBook)
                    }
                } else {
                    Menu("Aspect Ratio") {}.disabled(true)
                    Menu("Frame") {}.disabled(true)
                }
                Toggle("Dark Frame", isOn: Binding(get: { editor?.style.frameAppearance == .dark },
                                                   set: { dark in act(nil) { $0.setFrameAppearance(dark ? .dark : .light) } }))
                    .keyboardShortcut("d", modifiers: [.option, .command])
                    .disabled(editor.map { $0.style.frame == Style.DeviceFrame.none } ?? true)
                Button("Save Style as Preset…") { act(nil) { $0.showsSavePreset = true } }
                    .keyboardShortcut("s", modifiers: [.shift, .command])
                Menu("Apply Preset") {
                    ForEach(AppServices.shared.model?.presets ?? []) { preset in
                        Button(preset.name) { act(nil) { $0.applyPreset(preset) } }
                    }
                }
                Button("Crop Screen…") { act(nil) { $0.showsCropSheet = true } }
                    .keyboardShortcut("c", modifiers: [.option, .command])
                Divider()
                Button("Trim Start to Playhead") { act(nil) { $0.trimStartToPlayhead() } }
                    .keyboardShortcut("[", modifiers: .option)
                Button("Trim End to Playhead") { act(nil) { $0.trimEndToPlayhead() } }
                    .keyboardShortcut("]", modifiers: .option)
            }
            .disabled(editor?.player == nil)
        }
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

    /// An on/off part of the style, flipped as one undo step.
    private func styleBinding(_ key: WritableKeyPath<Style, Bool>, named name: String) -> Binding<Bool> {
        Binding(get: { editor?.style[keyPath: key] == true },
                set: { _ in act(nil) { $0.toggleStyle(key, named: name) } })
    }

    /// Delete follows the selection: a caption, a zoom, a blur, or a section.
    private var deleteTitle: String {
        if editor?.selectedCaption != nil { return "Delete Caption" }
        if editor?.selectedZoom != nil { return "Delete Zoom" }
        return editor?.selectedBlur != nil ? "Delete Blur" : "Delete Section"
    }

    /// Runs `action` on the Editor, unless a text field is being edited:
    /// then the key goes to the text, because a menu shortcut with no ⌘
    /// would otherwise take Space and the arrows away from typing.
    private func act(_ key: TextKey?, _ action: (EditorModel) -> Void) {
        if let key, let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable {
            key.send(to: text)
            return
        }
        guard let editor else { return }
        withMotion(Motion.quick) { action(editor) }
    }
}

/// The keys the Playback menu uses, as a text view would handle them.
enum TextKey {
    case space, left, right, shiftLeft, shiftRight, home, end
    case text(String)
    case deleteBackward
    /// Return: ends the edit in a text field, as typing Return there would.
    case newline

    @MainActor func send(to text: NSTextView) {
        switch self {
        case .space: text.insertText(" ", replacementRange: text.selectedRange())
        case .left: text.moveLeft(nil)
        case .right: text.moveRight(nil)
        case .shiftLeft: text.moveLeftAndModifySelection(nil)
        case .shiftRight: text.moveRightAndModifySelection(nil)
        case .home: text.moveToBeginningOfLine(nil)
        case .end: text.moveToEndOfLine(nil)
        case .text(let string): text.insertText(string, replacementRange: text.selectedRange())
        case .deleteBackward: text.deleteBackward(nil)
        case .newline: text.insertNewline(nil)
        }
    }
}
