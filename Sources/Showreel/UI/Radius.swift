import SwiftUI

/// Corner radii. Inner corners are concentric: inner = outer - inset.
/// Use `.continuous` style everywhere.
enum Radius {
    /// Timeline blocks (clip, zoom, caption), chips, key caps.
    static let xs: CGFloat = 6
    /// Controls drawn by hand, the accent swatch tiles.
    static let sm: CGFloat = 8
    /// Project card thumbnails and row hover fills.
    static let thumbnail: CGFloat = 10
    /// Cards and grouped surfaces.
    static let md: CGFloat = 12
    /// Widgets and large previews.
    static let lg: CGFloat = 18
    /// Custom floating glass that is not a capsule.
    static let xl: CGFloat = 26
    /// The Camera Bubble's rounded-square shape, as a fraction of its size.
    static let bubbleSquareRatio: CGFloat = 0.24

    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
