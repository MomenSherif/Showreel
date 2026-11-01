import AppKit
import SwiftUI

/// Every animation in the app. Views never write durations or springs.
/// Reduce Motion turns movement into a short fade (`Motion.resolved`) and
/// stops loops.
enum Motion {
    /// Hover fills and lifts.
    static let hover = Animation.easeOut(duration: 0.12)
    /// Presses and small flips (a toggle's symbol).
    static let quick = Animation.snappy(duration: 0.18)
    /// General UI changes: a section expanding, the inspector swapping.
    static let ui = Animation.smooth(duration: 0.25)
    /// Selection moving through a live list or timeline.
    static let select = Animation.snappy(duration: 0.15)
    /// Panels, popovers of our own, and the Camera Bubble's hover controls appearing.
    static let appear = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// Anything leaving. Faster than it came.
    static let dismiss = Animation.easeIn(duration: 0.15)
    /// Long, smooth moves: the Camera Bubble snapping to a corner.
    static let glide = Animation.spring(response: 0.45, dampingFraction: 0.82)
    /// Numbers changing (time, file size). Use with `.contentTransition(.numericText())`.
    static let numberRoll = Animation.snappy(duration: 0.2)
    /// Rows or cards inserted and removed.
    static let listChange = Animation.smooth(duration: 0.3)
    /// One Countdown number: scale 0.9 to 1 and fade in.
    static let countdownTick = Animation.spring(response: 0.4, dampingFraction: 0.75)
    /// The recording dot. Stops under Reduce Motion.
    static let pulse = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    /// The Reduce Motion stand-in for movement.
    static let fade = Animation.easeInOut(duration: 0.2)

    /// AppKit window moves (the Camera Bubble gliding to a snap point), in
    /// seconds. Zero under Reduce Motion: the window jumps.
    static var windowGlide: TimeInterval { reduceMotion ? 0 : 0.28 }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The animation to use right now: the fade under Reduce Motion, or nil
    /// for loops, which then do not run.
    static func resolved(_ animation: Animation, isLoop: Bool = false) -> Animation? {
        guard reduceMotion else { return animation }
        return isLoop ? nil : fade
    }
}

/// `withAnimation` that respects Reduce Motion.
@discardableResult
func withMotion<Result>(_ animation: Animation, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.resolved(animation), body)
}
