import Foundation
import SwiftData
import ShowreelKit

/// One recording and everything done to it in the editor (see docs/GLOSSARY.md).
/// The recorded tracks live in a folder named after `uuid`; edits are added
/// to this model story by story.
@Model
final class Project {
    var title: String
    var createdAt: Date = Date.now
    /// Length of the recording in seconds.
    var duration: Double = 0
    /// A stable id for the project folder, links, and the agent CLI.
    var uuid: UUID = UUID()

    init(title: String, duration: Double = 0) {
        self.title = ProjectTitle.clean(title)
        self.duration = duration
    }
}

/// The library's pages. Snapshot mode walks through every case.
enum LibraryPage: String, CaseIterable, Identifiable {
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Projects"
        }
    }

    var symbol: String {
        switch self {
        case .all: "film.stack"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    var page: LibraryPage? = .all
    var selection: PersistentIdentifier?
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Adds a project for a finished recording and selects it.
    @discardableResult
    func addProject(title: String = "", duration: Double = 0) -> Project {
        let project = Project(title: title, duration: duration)
        container.mainContext.insert(project)
        selection = project.id
        return project
    }
}
