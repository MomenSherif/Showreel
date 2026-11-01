import Foundation

/// How the timeline maps seconds to points, and where the ruler puts its
/// labels (S-015, S-017).
public struct TimelineScale: Equatable, Sendable {
    /// Points per second of recording.
    public var pointsPerSecond: Double

    public init(pointsPerSecond: Double) {
        self.pointsPerSecond = max(pointsPerSecond, 0.01)
    }

    /// The scale that shows `duration` in `width` points.
    public static func fit(duration: Double, width: Double) -> TimelineScale {
        TimelineScale(pointsPerSecond: width / max(duration, 0.1))
    }

    public func x(at seconds: Double) -> Double { seconds * pointsPerSecond }
    public func seconds(at x: Double) -> Double { x / pointsPerSecond }

    /// Label spacings the ruler may use, in seconds.
    static let steps: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]

    /// Seconds between labeled ticks: the smallest step at least
    /// `minSpacing` points apart.
    public func labelStep(minSpacing: Double = 72) -> Double {
        Self.steps.first { $0 * pointsPerSecond >= minSpacing } ?? Self.steps[Self.steps.count - 1]
    }

    /// Small unlabeled ticks between labels: five or ten per label, never
    /// closer than `minSpacing` points.
    public func tickStep(minSpacing: Double = 8) -> Double {
        let label = labelStep()
        let ten = label / 10
        return ten * pointsPerSecond >= minSpacing ? ten : label / 5
    }

    /// "0:01" when labels fall on whole seconds, "0:00.5" for tenths.
    public func label(_ seconds: Double) -> String {
        labelStep() < 1 ? TimeText.precise(seconds + 0.0001) : TimeText.clock(seconds + 0.0001)
    }
}

/// Where the playhead lands for the Playback commands (S-016).
public enum PlayheadMove {
    /// The editor's frame rate.
    public static let fps = 60.0

    /// `frames` frames from `time`, on the frame grid, inside 0...duration.
    public static func step(from time: Double, frames: Int, duration: Double) -> Double {
        let index = (time * fps).rounded() + Double(frames)
        return clamp(index / fps, duration: duration)
    }

    /// `seconds` from `time`, inside 0...duration.
    public static func jump(from time: Double, by seconds: Double, duration: Double) -> Double {
        clamp(time + seconds, duration: duration)
    }

    public static func clamp(_ time: Double, duration: Double) -> Double {
        min(max(time, 0), max(duration, 0))
    }
}
