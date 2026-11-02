import AppKit
import Observation
import ShowreelKit

/// The values set in Settings (S-045), kept in `Store.defaults`. Observable,
/// so the Record menu and the Settings window follow every change.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let recordShortcut = "record.shortcut"
        static let countdown = "record.countdown"
        static let exportsFolder = "export.folder"
        static let export = "export.settings"
    }

    /// Starts and stops recording from any app. Set it with `setRecordShortcut(_:)`,
    /// which checks that the system gives it to Showreel.
    private(set) var recordShortcut = Shortcut.decode(Store.defaults.data(forKey: Key.recordShortcut))

    /// The seconds of Countdown before recording; 0 is Off.
    var countdownSeconds = CountdownLength.resolve(Store.defaults.object(forKey: Key.countdown) as? Int) {
        didSet { Store.defaults.set(countdownSeconds, forKey: Key.countdown) }
    }

    /// The Export sheet starts with these and writes back what was picked.
    var exportSettings = ExportSettings.decode(Store.defaults.data(forKey: Key.export)) {
        didSet { Store.defaults.set(exportSettings.encoded(), forKey: Key.export) }
    }

    /// Where the Export save panel opens. Movies until one is chosen, and
    /// again if the chosen folder is gone.
    var exportsFolder: URL {
        get {
            access(keyPath: \.exportsFolder)
            if let path = Store.defaults.string(forKey: Key.exportsFolder) {
                var isFolder: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue {
                    return URL(fileURLWithPath: path, isDirectory: true)
                }
            }
            return URL.moviesDirectory
        }
        set {
            withMutation(keyPath: \.exportsFolder) {
                Store.defaults.set(newValue.path(percentEncoded: false), forKey: Key.exportsFolder)
            }
        }
    }

    enum ShortcutProblem: Equatable {
        /// No ⌘, ⌥, or ⌃.
        case needsModifier
        /// The system refused it: another app holds it.
        case taken(String)

        var message: String {
            switch self {
            case .needsModifier: "Add ⌘, ⌥, or ⌃ so the shortcut works in any app."
            case .taken(let keys): "Another app uses \(keys). Try a different shortcut."
            }
        }
    }

    /// Makes `shortcut` the Record Shortcut, or says why not and keeps the old one.
    @discardableResult
    func setRecordShortcut(_ shortcut: Shortcut) -> ShortcutProblem? {
        guard shortcut.worksInAnyApp else { return .needsModifier }
        guard shortcut != recordShortcut else { return nil }
        guard HotKeys.replaceRecord(with: shortcut) else { return .taken(shortcut.display) }
        recordShortcut = shortcut
        Store.defaults.set(shortcut.encoded(), forKey: Key.recordShortcut)
        return nil
    }
}
