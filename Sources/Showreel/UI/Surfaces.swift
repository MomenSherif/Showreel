import AppKit
import SwiftUI

/// Colors for the surfaces Showreel draws itself. Window chrome, forms, and
/// lists use system backgrounds and never these.
enum Surfaces {
    /// A neutral custom surface: a little translucent so it takes the desktop tint.
    static let surface = Color.primary.opacity(0.05)
    /// The same surface under the pointer.
    static let surfaceHover = Color.primary.opacity(0.09)
    /// A chosen tile or an input that is on, on floating glass.
    static let selected = Color.primary.opacity(0.13)
    /// Thin lines between custom areas (timeline rows, the transport bar).
    static let hairline = Color(nsColor: .separatorColor)
    /// The one warning color. Always paired with an icon and words.
    static let warning = Color(nsColor: .systemOrange)
    /// Behind the editor canvas, like Preview and Keynote.
    static let canvasBackdrop = Color(nsColor: .underPageBackgroundColor)
    /// A dark scrim under text that sits on top of video or the desktop.
    static let scrim = Color.black.opacity(0.45)
    /// Text on `scrim`. Fixed, because the scrim is dark in both modes.
    static let onScrim = Color.white
    /// Soft shadow under content that floats a little: cards, the Camera Bubble.
    static let shadow = Color.black.opacity(0.10)
    /// The same shadow when the pointer is over a card.
    static let shadowHover = Color.black.opacity(0.18)
}

/// Colors that carry a meaning in recording and on the timeline. Each one is
/// always shown with a symbol or a word too, never alone.
enum Media {
    /// Start Recording, the recording dot, and the menu bar extra while recording.
    static let record = Color(nsColor: .systemRed)
    /// The timeline playhead line and its cap.
    static let playhead = Color(nsColor: .systemRed)

    /// Track fills. White label text on each has a contrast of 4.5:1 or more.
    enum Track {
        static let clip = Color(light: 0x3D63C9, dark: 0x3558B8, highContrastLight: 0x2B4FB0, highContrastDark: 0x2B4FB0)
        static let zoom = Color(light: 0x7444D8, dark: 0x6A3DCB, highContrastLight: 0x5B2FBF, highContrastDark: 0x5B2FBF)
        static let blur = Color(light: 0x9A4A14, dark: 0x8C4312, highContrastLight: 0x7E3B0F, highContrastDark: 0x7E3B0F)
        static let caption = Color(light: 0x0F7A6E, dark: 0x0D6E63, highContrastLight: 0x0A5F56, highContrastDark: 0x0A5F56)
        static let audio = Color(light: 0x2E7D32, dark: 0x2A7230, highContrastLight: 0x21632A, highContrastDark: 0x21632A)
        /// Text and symbols on any track fill.
        static let label = Color.white
        /// The empty lane behind a track's blocks.
        static let lane = Color.primary.opacity(0.04)
        /// Over the muted parts of the audio track (S-042).
        static let mutedBand = Color.black.opacity(0.35)
    }
}
