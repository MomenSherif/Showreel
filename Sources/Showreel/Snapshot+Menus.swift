import AppKit
import SwiftData
import SwiftUI

extension Snapshot {
    /// The editor's menus as menu-<name>-light.png and -dark.png (S-044).
    static let editorMenus = ["Edit", "View", "Clip", "Playback"]

    /// Draws each editor menu from the real menu bar items (title, shortcut,
    /// submenu). A live menu cannot be opened in an app that is not active,
    /// and a snapshot run must not take the front from the person using the
    /// Mac, so the menu is drawn, not opened. Enabled states are not drawn: an
    /// inactive app has no focused editor, so every editor command reads as
    /// off. The self-test checks the states.
    static func captureMenus(model: AppModel, dir: String, only: Set<String>?) async {
        let names = editorMenus.filter { only?.contains("menu-\($0.lowercased())") ?? true }
        guard !names.isEmpty else { return }
        let title = SeedData.samples.first?.title
        let editorWindow = { NSApp.windows.first { $0.title == title && $0.isVisible } }
        if editorWindow() == nil,
           let project = (try? model.context.fetch(FetchDescriptor<Project>()))?.first(where: { $0.title == title }) {
            AppServices.shared.openProject(project.uuid)
        }
        for _ in 0..<30 where EditorModel.newest?.player == nil { try? await Task.sleep(for: .seconds(0.1)) }
        guard let window = editorWindow() else {
            print("SNAPSHOT no editor for the menus")
            return
        }
        // The focused editor drives the menus' titles and enabled states.
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(0.6))
        for name in names {
            guard let menu = NSApp.mainMenu?.item(withTitle: name)?.submenu else { continue }
            menu.update()
            let rows = MenuRow.visible(menu.items)
            for scheme in [ColorScheme.light, .dark] {
                NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                let renderer = ImageRenderer(content: MenuPicture(title: name, rows: rows)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 2
                let path = "\(dir)/menu-\(name.lowercased())-\(scheme == .light ? "light" : "dark").png"
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    print("SNAPSHOT failed \(path)")
                    continue
                }
                try? png.write(to: URL(fileURLWithPath: path))
                print("SNAPSHOT \(path)")
            }
        }
    }
}

/// One menu item, read from the menu bar.
private struct MenuRow: Identifiable {
    let id = UUID()
    let title: String
    let shortcut: String
    let isSeparator, hasSubmenu: Bool

    /// The items as the menu bar shows them: hidden ones left out, and no
    /// separator at either end or next to another.
    @MainActor static func visible(_ items: [NSMenuItem]) -> [MenuRow] {
        var rows: [MenuRow] = []
        for item in items where !item.isHidden {
            if item.isSeparatorItem, rows.last?.isSeparator ?? true { continue }
            rows.append(MenuRow(item))
        }
        if rows.last?.isSeparator == true { rows.removeLast() }
        return rows
    }

    @MainActor init(_ item: NSMenuItem) {
        title = item.title
        isSeparator = item.isSeparatorItem
        hasSubmenu = item.submenu != nil
        shortcut = Self.format(item.keyEquivalent, item.keyEquivalentModifierMask)
    }

    /// "⌥⌘G", "⇧←", "Space": the way the menu bar shows a shortcut.
    static func format(_ key: String, _ mask: NSEvent.ModifierFlags) -> String {
        guard let scalar = key.unicodeScalars.first else { return "" }
        let named: [Int: String] = [
            0x20: "Space", 0x0D: "↩", 0x08: "⌫", 0x7F: "⌫",
            NSLeftArrowFunctionKey: "←", NSRightArrowFunctionKey: "→",
            NSUpArrowFunctionKey: "↑", NSDownArrowFunctionKey: "↓",
            NSHomeFunctionKey: "↖", NSEndFunctionKey: "↘",
        ]
        var text = ""
        if mask.contains(.control) { text += "⌃" }
        if mask.contains(.option) { text += "⌥" }
        if mask.contains(.shift) || (key.uppercased() == key && key.lowercased() != key) { text += "⇧" }
        if mask.contains(.command) { text += "⌘" }
        return text + (named[Int(scalar.value)] ?? key.uppercased())
    }
}

/// A menu drawn with system colors and the menu font.
private struct MenuPicture: View {
    let title: String
    let rows: [MenuRow]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    if row.isSeparator {
                        Divider().padding(.vertical, Space.xs)
                    } else {
                        HStack(spacing: Space.sm) {
                            Text(row.title)
                            Spacer(minLength: Space.xl)
                            Text(row.hasSubmenu ? "›" : row.shortcut).monospacedDigit()
                        }
                        .padding(.vertical, Space.xs)
                    }
                }
            }
            .padding(Space.sm)
            .frame(width: 320)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(.separator))
        }
        .font(.body)
        .padding(Space.lg)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
