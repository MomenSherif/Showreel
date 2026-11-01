import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftData
import SwiftUI
import ShowreelEngine
import ShowreelKit

/// Self-test checks for the store, the Library, the menus, and the panels (M1).
extension SelfTest {
    /// S-008: projects survive in the store with their fields.
    static func projects(_ model: AppModel) {
        let before = all(model).count
        let project = model.addProject(title: "  Self-test   recording ", duration: 12)
        check("adding a project adds one project", all(model).count == before + 1)
        check("the new project is selected", model.selection == project.uuid)
        check("the project title is cleaned", project.title == "Self-test recording")
        check("an empty title becomes Untitled Project", ProjectTitle.clean("  ") == ProjectTitle.untitled)
        check("a new recording gets a dated title", RecordController.defaultTitle().hasPrefix("Recording "))
        model.context.delete(project)
        try? model.context.save()
    }

    /// S-010: Rename, Duplicate, and Move to Trash, each with Undo.
    static func library(_ model: AppModel) {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let project = model.addProject(title: "Trash me", duration: 5)
        let id = project.uuid
        _ = try? ProjectStore.makeFolder(for: id)
        FileManager.default.createFile(atPath: ProjectStore.file(ProjectFiles.screen, of: id).path, contents: Data([1, 2, 3]))

        undo.beginUndoGrouping()
        ProjectStore.rename(project, to: "  Renamed  ", undo: undo)
        undo.endUndoGrouping()
        check("rename cleans the title", project.title == "Renamed")
        undo.undo()
        check("undo restores the old title", project.title == "Trash me")

        undo.beginUndoGrouping()
        let copy = ProjectStore.duplicate(project, in: model, undo: undo)
        undo.endUndoGrouping()
        check("duplicate copies the folder",
              FileManager.default.fileExists(atPath: ProjectStore.file(ProjectFiles.screen, of: copy.uuid).path))
        check("duplicate is named copy", copy.title == "Trash me copy")
        ProjectStore.moveToTrash(copy, in: model, undo: nil)

        let before = all(model).count
        undo.beginUndoGrouping()
        ProjectStore.moveToTrash(project, in: model, undo: undo)
        undo.endUndoGrouping()
        check("move to trash removes the card", all(model).count == before - 1 && model.project(id) == nil)
        check("move to trash moves the folder", !FileManager.default.fileExists(atPath: ProjectStore.folder(for: id).path))
        check("undo says Move to Trash", undo.undoActionName == "Move to Trash")
        undo.undo()
        check("undo brings the card back", model.project(id) != nil)
        check("undo brings the folder back",
              FileManager.default.fileExists(atPath: ProjectStore.file(ProjectFiles.screen, of: id).path))
        undo.redo()
        check("redo moves it to the trash again", model.project(id) == nil)
    }

    /// S-002: the menu bar item's menu and the Record menu.
    static func menuBar() {
        StatusItem.shared.update()
        let titles = StatusItem.shared.itemTitles
        check("menu bar menu has New Recording, Open Library, Settings, Quit",
              ["New Recording", "Open Library", "Settings…", "Quit Showreel"].allSatisfy(titles.contains),
              titles.joined(separator: ", "))
        let mainMenu = NSApp.mainMenu?.items.map(\.title) ?? []
        check("the menu bar has a Record menu", mainMenu.contains("Record"), mainMenu.joined(separator: ", "))
    }

    /// S-011: floating chrome, the Camera Bubble included, never shows up in a recording.
    static func panels() {
        let panel = FloatingPanel(size: CGSize(width: Space.md, height: Space.md), options: .init(), content: Color.clear)
        check("floating panels are left out of screen capture", panel.sharingType == .none)
        check("floating panels are not in the Window menu", panel.isExcludedFromWindowsMenu)
        check("the Camera Bubble is Medium by default", CameraBubble.shared.diameter == Layout.bubbleSizes[1])
        bubbleSnap()
    }
}
