import AppKit
import SwiftData
import SwiftUI

/// Lets AppKit code (the menu bar item, hotkeys, the recorder) open SwiftUI
/// windows and reach the model. The Library attaches it when it first appears.
final class AppServices {
    static let shared = AppServices()

    /// Set when the app starts.
    var model: AppModel?
    private var openWindowAction: OpenWindowAction?
    private var undoProvider: (() -> UndoManager?)?

    /// The menu commands hand over their open-window action at launch.
    func adopt(openWindow: OpenWindowAction) {
        openWindowAction = openWindow
    }

    /// The Library hands over its undo manager when it appears.
    func attach(model: AppModel, openWindow: OpenWindowAction, undo: @escaping () -> UndoManager?) {
        self.model = model
        openWindowAction = openWindow
        undoProvider = undo
    }

    var undoManager: UndoManager? { undoProvider?() }

    func openLibrary() {
        NSApp.activate()
        openWindowAction?(id: "library")
    }

    func openProject(_ id: UUID) {
        NSApp.activate()
        model?.selection = id
        openWindowAction?(id: "editor", value: id)
    }

    func openWelcome() {
        NSApp.activate()
        openWindowAction?(id: "welcome")
    }

    func openSettings() {
        NSApp.activate()
        // The Settings scene answers this selector; it is what Command-comma sends.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func recentProjects(limit: Int) -> [Project] {
        guard let model else { return [] }
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { !$0.isSaving },
                                                  sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? model.context.fetch(descriptor)) ?? []
    }
}
