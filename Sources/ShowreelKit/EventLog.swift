import CoreGraphics
import Foundation

/// Everything that happened during a recording besides the pixels, saved as
/// `events.json`. Times are seconds of recording time (pauses removed).
/// Positions are normalized to the recorded source: (0, 0) is its top-left
/// corner and (1, 1) its bottom-right.
public struct EventLog: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public var t: Double
        public var x: Double
        public var y: Double
        public init(t: Double, x: Double, y: Double) { self.t = t; self.x = x; self.y = y }
    }

    public struct Click: Codable, Equatable, Sendable {
        public enum Button: String, Codable, Sendable { case left, right, other }
        public var t: Double
        public var x: Double
        public var y: Double
        public var button: Button
        public init(t: Double, x: Double, y: Double, button: Button) {
            self.t = t; self.x = x; self.y = y; self.button = button
        }
    }

    public struct Key: Codable, Equatable, Sendable {
        public var t: Double
        public var keyCode: UInt16
        public init(t: Double, keyCode: UInt16) { self.t = t; self.keyCode = keyCode }
    }

    public struct Range: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        public init(start: Double, end: Double) { self.start = start; self.end = end }
    }

    public static let currentVersion = 1

    public var version = EventLog.currentVersion
    /// The recorded source in global screen points, top-left origin.
    public var source: CGRect
    /// Cursor position, sampled at 60 Hz while it is over the source.
    public var cursor: [Point] = []
    public var clicks: [Click] = []
    /// Key presses. Empty when Showreel has no Accessibility access.
    public var keys: [Key] = []
    /// Camera Bubble center, logged each time it moves.
    public var bubble: [Point] = []
    /// Ranges when the Camera Bubble was hidden.
    public var cameraHidden: [Range] = []
    /// The text caret while typing, at most 4 times a second (S-030).
    /// Empty without Accessibility access, or in logs made before S-030.
    public var caret: [Point] = []

    public init(source: CGRect) { self.source = source }

    enum CodingKeys: String, CodingKey { case version, source, cursor, clicks, keys, bubble, cameraHidden, caret }

    /// Fields added after version 1 are optional, so older logs still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        source = try c.decode(CGRect.self, forKey: .source)
        cursor = try c.decodeIfPresent([Point].self, forKey: .cursor) ?? []
        clicks = try c.decodeIfPresent([Click].self, forKey: .clicks) ?? []
        keys = try c.decodeIfPresent([Key].self, forKey: .keys) ?? []
        bubble = try c.decodeIfPresent([Point].self, forKey: .bubble) ?? []
        cameraHidden = try c.decodeIfPresent([Range].self, forKey: .cameraHidden) ?? []
        caret = try c.decodeIfPresent([Point].self, forKey: .caret) ?? []
    }

    /// A global top-left point as a position inside the source, or nil when it is outside.
    public func normalized(_ point: CGPoint) -> CGPoint? {
        guard source.width > 0, source.height > 0, source.contains(point) else { return nil }
        return CGPoint(x: (point.x - source.minX) / source.width,
                       y: (point.y - source.minY) / source.height)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> EventLog {
        try JSONDecoder().decode(EventLog.self, from: data)
    }
}
