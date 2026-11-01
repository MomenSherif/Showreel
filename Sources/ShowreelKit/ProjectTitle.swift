import Foundation

/// Rules for project titles. Logic lives in this library so tests can run it
/// without the app. Put parsers, timing rules, and data rules here too.
public enum ProjectTitle {
    /// The title a project gets when the person leaves it empty.
    public static let untitled = "Untitled Project"

    /// Trims spaces and line breaks, collapses inner runs of spaces, and
    /// falls back to "Untitled Project" for an empty title.
    public static func clean(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? untitled : words.joined(separator: " ")
    }
}
