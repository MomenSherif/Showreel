import Foundation

/// The files in one project folder. Every track is its own file, so the
/// editor can redraw the cursor, zooms, and camera without losing quality.
public enum ProjectFiles {
    /// The screen, recorded without the cursor.
    public static let screen = "screen.mov"
    public static let camera = "camera.mov"
    public static let microphone = "mic.m4a"
    public static let systemAudio = "system.m4a"
    /// Cursor moves, clicks, key presses, and Camera Bubble moves (`EventLog`).
    public static let events = "events.json"
    public static let thumbnail = "thumbnail.jpg"

    public static let all = [screen, camera, microphone, systemAudio, events, thumbnail]

    /// The project folder's name: the project's id, so renaming never moves files.
    public static func folderName(for id: UUID) -> String { id.uuidString }
}

/// What gets recorded.
public enum SourceKind: String, Codable, Sendable, CaseIterable {
    case display, window, area

    public var title: String {
        switch self {
        case .display: "Display"
        case .window: "Window"
        case .area: "Area"
        }
    }
}
