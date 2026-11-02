import Foundation

/// A key with modifiers, like ⌃⌥⌘R: the Record Shortcut (S-045).
public struct Shortcut: Codable, Equatable, Sendable {
    /// The virtual key code (kVK_ANSI_R is 15), for the system hotkey.
    public var keyCode: UInt16
    /// The key's character as typed without modifiers, lowercased ("r").
    public var key: String
    public var control, option, shift, command: Bool

    public init(keyCode: UInt16, key: String, control: Bool = false, option: Bool = false,
                shift: Bool = false, command: Bool = false) {
        self.keyCode = keyCode
        self.key = key.lowercased()
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
    }

    /// ⌃⌥⌘R, the shortcut since S-007.
    public static let record = Shortcut(keyCode: 15, key: "r", control: true, option: true, command: true)

    /// The way menus show it: modifiers in Apple's order, then the key.
    public var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + keyName
    }

    /// What VoiceOver reads: "Control Option Command R".
    public var spoken: String {
        let names = [(control, "Control"), (option, "Option"), (shift, "Shift"), (command, "Command")]
        return (names.filter(\.0).map(\.1) + [keyName == " " ? "Space" : keyName]).joined(separator: " ")
    }

    private var keyName: String { key == " " ? "Space" : key.uppercased() }

    /// A shortcut that works in any app needs ⌘, ⌥, or ⌃; Shift alone would
    /// steal a capital letter from every text field.
    public var worksInAnyApp: Bool { control || option || command }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// The stored shortcut, or ⌃⌥⌘R when there is none or it cannot be read.
    public static func decode(_ data: Data?) -> Shortcut {
        data.flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }.flatMap { $0.worksInAnyApp ? $0 : nil } ?? .record
    }
}

/// The seconds of Countdown before recording starts (S-045). Off is 0.
public enum CountdownLength {
    public static let choices = [0, 3, 5, 10]
    public static let standard = 3

    /// A stored value, or 3 when it is missing or not one of the choices.
    public static func resolve(_ stored: Int?) -> Int {
        stored.flatMap { choices.contains($0) ? $0 : nil } ?? standard
    }

    public static func title(_ seconds: Int) -> String { seconds == 0 ? "Off" : "\(seconds) seconds" }
}
