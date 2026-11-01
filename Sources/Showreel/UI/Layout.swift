import SwiftUI

/// Fixed sizes for windows, columns, and custom parts. Spacing lives in `Space`.
enum Layout {
    // Library
    static let cardMinWidth: CGFloat = 220
    /// Thumbnail aspect ratio (16:10).
    static let thumbnailAspect: CGFloat = 16.0 / 10.0

    // Editor
    static let inspectorWidth = (min: CGFloat(280), ideal: CGFloat(300), max: CGFloat(340))
    static let timelineHeight = (min: CGFloat(160), ideal: CGFloat(220))
    static let trackHeaderWidth: CGFloat = 28
    static let trackHeight: CGFloat = 36
    static let playheadWidth: CGFloat = 2
    static let selectionRing: CGFloat = 2

    // Floating recording chrome
    static let recordPanel = CGSize(width: 600, height: 56)
    static let countdownCircle: CGFloat = 160
    /// Distance of the Recording Controls from the bottom of the display.
    static let controlsInset: CGFloat = 24

    // Camera Bubble
    static let bubbleSizes: [CGFloat] = [120, 180, 240] // Small, Medium, Large
    /// The window that holds the bubble's hover controls (S-013).
    static let bubbleControls = CGSize(width: 280, height: 48)
    /// Snaps to a corner or an edge midpoint within this distance.
    static let snapDistance: CGFloat = 24

    // Windows
    static let welcomeWidth: CGFloat = 480
    static let settingsWidth: CGFloat = 520
}
