import AppKit
import AVFoundation
import SwiftData
import ShowreelKit

/// Where project folders live, and the file actions on them.
///   ~/Movies/Showreel/<uuid>/screen.mov, camera.mov, mic.m4a, system.m4a, events.json, thumbnail.jpg
/// Test, snapshot, and self-test runs (APP_STORE set) use /tmp/Showreel-projects instead.
@MainActor
enum ProjectStore {
    static var root: URL {
        let url: URL
        if Store.isOverridden {
            url = URL(fileURLWithPath: "/tmp/Showreel-projects", isDirectory: true)
        } else {
            url = URL.moviesDirectory.appending(path: "Showreel", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func folder(for id: UUID) -> URL {
        root.appending(path: ProjectFiles.folderName(for: id), directoryHint: .isDirectory)
    }

    static func file(_ name: String, of id: UUID) -> URL {
        folder(for: id).appending(path: name)
    }

    @discardableResult
    static func makeFolder(for id: UUID) throws -> URL {
        let url = folder(for: id)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// True when the recording a finished project needs is gone.
    static func filesMissing(_ project: Project) -> Bool {
        !project.isSaving && !FileManager.default.fileExists(atPath: file(ProjectFiles.screen, of: project.uuid).path)
    }

    // MARK: Thumbnails

    private static var thumbnails: [UUID: NSImage] = [:]

    static func thumbnail(for id: UUID) -> NSImage? {
        if let cached = thumbnails[id] { return cached }
        let image = NSImage(contentsOf: file(ProjectFiles.thumbnail, of: id))
        thumbnails[id] = image
        return image
    }

    /// Writes thumbnail.jpg from a frame half a second into screen.mov.
    static func makeThumbnail(for id: UUID) async {
        let asset = AVURLAsset(url: file(ProjectFiles.screen, of: id))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 600)
        guard let (cgImage, _) = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return }
        try? data.write(to: file(ProjectFiles.thumbnail, of: id))
        thumbnails[id] = nil
    }

    // MARK: Actions (S-010)

    /// Moves a folder to the Trash and returns where it went. Test and
    /// snapshot runs use /tmp/Showreel-trash, never the person's Trash.
    @discardableResult
    static func trash(_ url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if Store.isOverridden {
            let bin = URL(fileURLWithPath: "/tmp/Showreel-trash", isDirectory: true)
            try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let target = bin.appending(path: "\(url.lastPathComponent)-\(UUID().uuidString.prefix(8))")
            return (try? FileManager.default.moveItem(at: url, to: target)) != nil ? target : nil
        }
        var result: NSURL?
        try? FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }

    static func rename(_ project: Project, to title: String, undo: UndoManager?) {
        let old = project.title
        let new = ProjectTitle.clean(title)
        guard new != old else { return }
        project.title = new
        undo?.registerUndo(withTarget: project) { $0.title = old }
        undo?.setActionName("Rename")
    }

    static func showInFinder(_ project: Project) {
        let folder = folder(for: project.uuid)
        if FileManager.default.fileExists(atPath: folder.path) {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([root])
        }
    }

    /// Copies the folder and the edits to a new project named "<title> copy".
    @discardableResult
    static func duplicate(_ project: Project, in model: AppModel, undo: UndoManager?) -> Project {
        let newID = UUID()
        try? FileManager.default.copyItem(at: folder(for: project.uuid), to: folder(for: newID))
        let copy = ProjectRecord(project).makeProject(newID: newID, title: "\(project.title) copy")
        model.context.insert(copy)
        try? model.context.save()
        model.selection = newID
        undo?.registerUndo(withTarget: model) { model in
            if let made = model.project(newID) { moveToTrash(made, in: model, undo: nil) }
        }
        undo?.setActionName("Duplicate")
        return copy
    }

    /// Moves the folder to the Trash and removes the card. Undo puts both back.
    static func moveToTrash(_ project: Project, in model: AppModel, undo: UndoManager?) {
        let record = ProjectRecord(project)
        let original = folder(for: project.uuid)
        let trashed = trash(original)
        if model.selection == project.uuid { model.selection = nil }
        model.context.delete(project)
        try? model.context.save()
        thumbnails[record.uuid] = nil
        let trashURL = trashed
        undo?.registerUndo(withTarget: model) { [weak undo] model in
            restore(record, from: trashURL, to: original, in: model, undo: undo)
        }
        undo?.setActionName("Move to Trash")
    }

    private static func restore(_ record: ProjectRecord, from trash: URL?, to original: URL,
                                in model: AppModel, undo: UndoManager?) {
        if let trash, FileManager.default.fileExists(atPath: trash.path) {
            try? FileManager.default.moveItem(at: trash, to: original)
        }
        model.context.insert(record.makeProject())
        try? model.context.save()
        model.selection = record.uuid
        // Redo trashes it again.
        undo?.registerUndo(withTarget: model) { [weak undo] model in
            if let project = model.project(record.uuid) { moveToTrash(project, in: model, undo: undo) }
        }
        undo?.setActionName("Move to Trash")
    }
}
