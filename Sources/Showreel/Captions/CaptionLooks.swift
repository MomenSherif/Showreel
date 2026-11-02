import CoreText
import Foundation
import Observation
import ShowreelKit

/// The caption styles the person saved (S-057), for every project. Kept in
/// `Store.defaults`, so test runs start with none.
@MainActor
@Observable
final class CaptionLooks {
    static let shared = CaptionLooks()

    private static let key = "captions.savedStyles"

    private(set) var saved = SavedCaptionLooks.decode(Store.defaults.data(forKey: key)) {
        didSet { Store.defaults.set(saved.encoded(), forKey: Self.key) }
    }

    /// Saves the look of `style` as `name`.
    @discardableResult
    func save(_ style: CaptionStyle, named name: String) -> CaptionLook { saved.save(style, named: name) }

    func delete(_ id: CaptionLook.ID) { saved.delete(id) }

    func rename(_ id: CaptionLook.ID, to name: String) { saved.rename(id, to: name) }

    /// The named style `style` looks like, or nil for a look of its own.
    func match(_ style: CaptionStyle) -> CaptionLook? { saved.match(style) }

    /// Every font family on this Mac, for the Font menu, read once.
    static let fontFamilies: [String] = ((CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? [])
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}
