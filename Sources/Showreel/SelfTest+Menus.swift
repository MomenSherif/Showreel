import AppKit
import ShowreelKit

extension SelfTest {
    /// System items that are fine without a shortcut of ours: AppKit adds them.
    /// Edit > Delete is the text-field one; the editor's is Clip > Delete Section (⌫).
    static let systemItems: Set<String> = [
        "Edit > Start Dictation…", "Edit > Emoji & Symbols", "Edit > Delete", "Edit > Paste and Match Style",
        "View > Show Tab Bar", "View > Hide Tab Bar", "View > Show All Tabs", "View > Customize Toolbar…",
    ]

    /// The editor commands with no shortcut, as "Menu > Item". Submenus
    /// (Aspect Ratio, Apply Preset, Find…) are lists to pick from, not commands.
    static func commandsWithoutShortcut(in menus: [String]) -> [String] {
        menus.flatMap { name -> [String] in
            guard let menu = NSApp.mainMenu?.item(withTitle: name)?.submenu else { return ["\(name) (missing)"] }
            menu.update()
            return menu.items
                .filter { !$0.isSeparatorItem && !$0.isHidden && $0.submenu == nil && !$0.title.isEmpty }
                .filter(\.keyEquivalent.isEmpty)
                .map { "\(name) > \($0.title)" }
                .filter { !systemItems.contains($0) }
        }
    }

    static func menuTitles(_ name: String) -> [String] {
        NSApp.mainMenu?.item(withTitle: name)?.submenu?.items.map(\.title) ?? []
    }

    /// S-044: every editor action is in the menu bar with a shortcut.
    static func menus(_ editor: EditorModel) async {
        let missing = commandsWithoutShortcut(in: ["Edit", "View", "Clip", "Playback"])
        check("every Edit, View, Clip, and Playback command has a shortcut", missing.isEmpty, missing.joined(separator: ", "))
        let view = menuTitles("View")
        check("the View menu lists the six inspector sections",
              InspectorSection.allCases.allSatisfy { view.contains($0.title) }, view.joined(separator: ", "))
        let clip = menuTitles("Clip")
        let added = ["Unmute All", "Reduce Noise", "Generate Captions", "Edit Caption", "Show Captions", "Show Camera"]
        check("the Clip menu has the inspector's actions", added.allSatisfy(clip.contains), clip.joined(separator: ", "))

        // ⌘3 hides nothing: it shows the inspector at Effects.
        editor.showsInspector = false
        editor.showSection(.effects)
        check("a section command shows the inspector at that section", editor.showsInspector && editor.section == .effects)
        editor.showSection(.background)

        // Show Camera from the menu is one undo step, like the switch.
        let before = editor.style.cameraVisible
        editor.toggleStyle(\.cameraVisible, named: "Show Camera")
        let flipped = editor.style.cameraVisible != before
        editor.undoManager?.undo()
        check("Show Camera flips the camera and undoes in one step", flipped && editor.style.cameraVisible == before)
    }
}
