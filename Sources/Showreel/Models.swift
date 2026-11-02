import Foundation
import SwiftData
import ShowreelKit

/// One recording and everything done to it in the editor (see docs/GLOSSARY.md).
/// The tracks live in a folder named after `uuid` (`ProjectStore`).
/// Every property has a default, so older stores keep opening.
@Model
final class Project {
    var title: String = ProjectTitle.untitled
    var createdAt: Date = Date.now
    /// Length of the recording in seconds.
    var duration: Double = 0
    /// A stable id: the folder name, window value, and agent CLI handle.
    var uuid: UUID = UUID()
    /// `SourceKind` raw value.
    var sourceKind: String = SourceKind.display.rawValue
    /// Name of the display or window that was recorded.
    var sourceName: String = ""
    var hasCamera: Bool = false
    var hasMicrophone: Bool = false
    var hasSystemAudio: Bool = false
    /// Pixel size of screen.mov.
    var videoWidth: Int = 0
    var videoHeight: Int = 0
    /// Camera Bubble center, normalized to the recording (0...1, top-left origin).
    var bubbleX: Double = 0.86
    var bubbleY: Double = 0.80
    /// 0 Small, 1 Medium, 2 Large (`Layout.bubbleSizes`).
    var bubbleSize: Int = 1
    /// `BubbleStyle.Shape` raw value.
    var bubbleShape: String = "circle"
    /// True while the recording is still being written.
    var isSaving: Bool = false
    /// The Editor's cut, an `EditList` as JSON. Nil means uncut.
    var editsData: Data? = nil
    /// The Editor's style (background, padding, …), a `Style` as JSON. Nil means the default style.
    var styleData: Data? = nil
    /// The zooms, a `ZoomTrack` as JSON. Nil means not made yet: the editor
    /// makes them from the recording's clicks and typing the first time it opens (S-030).
    var zoomsData: Data? = nil

    init(title: String, duration: Double = 0, uuid: UUID = UUID()) {
        self.title = ProjectTitle.clean(title)
        self.duration = duration
        self.uuid = uuid
    }
}

/// A saved style (S-029). One preset can be the default for new recordings.
@Model
final class StylePreset {
    var name: String = "Preset"
    /// A `Style` as JSON, already without per-recording values (`Style.asPreset`).
    var styleData: Data = Data()
    var isDefault: Bool = false
    var createdAt: Date = Date.now

    init(name: String, style: Style) {
        self.name = name
        styleData = style.asPreset.encoded()
    }

    var style: Style { Style.decode(styleData) }
}

/// A plain copy of a project, so Move to Trash can be undone after the
/// model object is gone, and Duplicate can copy every field.
struct ProjectRecord {
    var title, sourceKind, sourceName, bubbleShape: String
    var createdAt: Date
    var duration: Double
    var uuid: UUID
    var hasCamera, hasMicrophone, hasSystemAudio: Bool
    var videoWidth, videoHeight, bubbleSize: Int
    var bubbleX, bubbleY: Double
    var editsData: Data?
    var styleData: Data?
    var zoomsData: Data?

    init(_ p: Project) {
        title = p.title; sourceKind = p.sourceKind; sourceName = p.sourceName
        createdAt = p.createdAt; duration = p.duration; uuid = p.uuid
        hasCamera = p.hasCamera; hasMicrophone = p.hasMicrophone; hasSystemAudio = p.hasSystemAudio
        videoWidth = p.videoWidth; videoHeight = p.videoHeight
        bubbleSize = p.bubbleSize; bubbleX = p.bubbleX; bubbleY = p.bubbleY
        bubbleShape = p.bubbleShape
        editsData = p.editsData
        styleData = p.styleData
        zoomsData = p.zoomsData
    }

    /// A model with these fields. With `newID`, a duplicate made now.
    func makeProject(newID: UUID? = nil, title newTitle: String? = nil) -> Project {
        let p = Project(title: newTitle ?? title, duration: duration, uuid: newID ?? uuid)
        p.createdAt = newID == nil ? createdAt : .now
        p.sourceKind = sourceKind; p.sourceName = sourceName
        p.hasCamera = hasCamera; p.hasMicrophone = hasMicrophone; p.hasSystemAudio = hasSystemAudio
        p.videoWidth = videoWidth; p.videoHeight = videoHeight
        p.bubbleSize = bubbleSize; p.bubbleX = bubbleX; p.bubbleY = bubbleY
        p.bubbleShape = bubbleShape
        p.editsData = editsData
        p.styleData = styleData
        p.zoomsData = zoomsData
        return p
    }
}

/// The library's snapshot pages. `empty` shows the library with no projects.
enum LibraryPage: String, CaseIterable, Identifiable {
    case library, empty

    var id: String { rawValue }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    /// Snapshot mode switches this to show the empty library.
    var page: LibraryPage = .library
    /// The selected project card in the Library.
    var selection: UUID?
    /// The card whose title is being edited inline.
    var renaming: UUID?
    var search = ""
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: Store.defaults.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { Store.defaults.set(settingsTab.rawValue, forKey: "settings.tab") }
    }

    init(container: ModelContainer) {
        self.container = container
    }

    var context: ModelContext { container.mainContext }

    func project(_ id: UUID?) -> Project? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    var selectedProject: Project? { project(selection) }

    /// Every preset, oldest first.
    var presets: [StylePreset] {
        (try? context.fetch(FetchDescriptor<StylePreset>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    /// Saves `style` as a preset. With `isDefault`, it becomes the only default.
    @discardableResult
    func savePreset(named name: String, style: Style, isDefault: Bool = false) -> StylePreset {
        let preset = StylePreset(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Preset" : name, style: style)
        context.insert(preset)
        if isDefault { makeDefault(preset) }
        try? context.save()
        return preset
    }

    /// Makes `preset` the style for new recordings; nil means none.
    func makeDefault(_ preset: StylePreset?) {
        for p in presets { p.isDefault = p === preset }
        try? context.save()
    }

    func deletePreset(_ preset: StylePreset) {
        context.delete(preset)
        try? context.save()
    }

    /// Adds a project and selects it. New recordings start with the default
    /// preset's style, when there is one (S-029).
    @discardableResult
    func addProject(title: String = "", duration: Double = 0, uuid: UUID = UUID()) -> Project {
        let project = Project(title: title, duration: duration, uuid: uuid)
        if let preset = presets.first(where: \.isDefault) { project.styleData = preset.styleData }
        context.insert(project)
        try? context.save()
        selection = project.uuid
        return project
    }
}
