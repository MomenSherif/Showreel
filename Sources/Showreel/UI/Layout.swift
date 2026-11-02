import SwiftUI

/// Fixed sizes for windows, columns, and custom parts. Spacing lives in `Space`.
enum Layout {
    // Library
    static let cardMinWidth: CGFloat = 220
    /// Thumbnail aspect ratio (16:10).
    static let thumbnailAspect: CGFloat = 16.0 / 10.0

    // Editor
    static let inspectorWidth = (min: CGFloat(280), ideal: CGFloat(300), max: CGFloat(340))
    /// Min fits the transport row, the ruler, and five lanes.
    static let timelineHeight = (min: CGFloat(248), ideal: CGFloat(276))
    static let trackHeaderWidth: CGFloat = 28
    static let trackHeight: CGFloat = 36
    static let playheadWidth: CGFloat = 2
    static let selectionRing: CGFloat = 2
    /// Width of one waveform bar on the audio track; bars sit one width apart.
    static let waveformBar: CGFloat = 2
    static let zoomSliderWidth: CGFloat = 96
    /// A download's bar in a Settings row or the inspector.
    static let progressWidth: CGFloat = 96
    /// The seam between two pieces of the clip after a split.
    static let clipSeam: CGFloat = 2
    /// Inspector tiles: gradient swatches and wallpaper thumbnails (16:10).
    static let swatch: CGFloat = 36
    static let wallpaperTile = CGSize(width: 64, height: 40)
    /// The frame area in the Crop Screen sheet.
    static let cropArea = CGSize(width: 640, height: 400)

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
    static let appIconSmall: CGFloat = 64
    static let appIconLarge: CGFloat = 96
    static let settingsWidth: CGFloat = 520
    static let shortcutFieldWidth: CGFloat = 96
    /// The export progress and finished popover (S-037, S-038).
    static let exportPopoverWidth: CGFloat = 320
}
