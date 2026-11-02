import CoreGraphics
import Foundation

/// How fast zooms move (S-033).
public enum ZoomSpeed: String, Codable, CaseIterable, Sendable {
    case slow, medium, fast

    public var title: String {
        switch self {
        case .slow: "Slow"
        case .medium: "Medium"
        case .fast: "Fast"
        }
    }

    /// The spring's natural frequency, in radians per second. A critically
    /// damped spring is 99% of the way there after about 6.6 / ω seconds:
    /// 1.5 s slow, 0.9 s medium, 0.6 s fast.
    public var omega: Double {
        switch self {
        case .slow: 4.5
        case .medium: 7.5
        case .fast: 11
        }
    }
}

/// The zoom camera for a whole recording (S-033): its scale and the spot it
/// looks at, moved by a critically damped spring toward each zoom, so it
/// eases in and out, pans between zooms back to back, and follows the
/// cursor without shaking or overshooting. Worked out once at 60 Hz, since
/// frames are drawn in any order when the playhead jumps.
public struct ZoomPath: Equatable, Sendable {
    public static let rate = 60.0

    struct Sample: Equatable, Sendable {
        var scale: Double
        var x: Double
        var y: Double
    }

    var samples: [Sample]

    /// No zooms: the whole recording all the time.
    public static let none = ZoomPath(samples: [])

    init(samples: [Sample]) { self.samples = samples }

    /// The camera for `track` over a recording `duration` seconds long.
    /// Positions are normalized to the whole recording.
    public init(track: ZoomTrack, cursor: CursorPath = CursorPath(), duration: Double, speed: ZoomSpeed = .medium) {
        guard let last = track.segments.last else { self = .none; return }
        // Run past the last zoom until the camera is back at rest.
        let end = max(duration, last.end) + 8 / speed.omega
        let count = Int((end * Self.rate).rounded(.up)) + 1
        let dt = 1 / Self.rate
        var scale = Spring(value: 1), x = Spring(value: 0.5), y = Spring(value: 0.5)
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        var index = 0
        // Out of a zoom the camera keeps looking at the last spot while it
        // zooms out, so it does not slide sideways on the way.
        var spot = CGPoint(x: 0.5, y: 0.5)
        for i in 0..<count {
            let t = Double(i) * dt
            while index < track.segments.count, track.segments[index].end < t { index += 1 }
            var targetScale = 1.0
            if index < track.segments.count, track.segments[index].start <= t {
                let zoom = track.segments[index]
                targetScale = min(max(zoom.scale, ZoomSegment.scaleRange.lowerBound), ZoomSegment.scaleRange.upperBound)
                if zoom.focus == .followCursor, let pointer = cursor.smoothed(at: t) {
                    // A zoom that just began starts on the cursor; after that the
                    // camera moves only to keep it inside the dead zone.
                    let entering = i == 0 || track.segments[index].start > t - dt
                    spot = entering ? pointer : Self.follow(pointer, from: spot, scale: targetScale)
                } else {
                    spot = CGPoint(x: zoom.x, y: zoom.y)
                }
            }
            if i > 0 {
                scale.step(toward: targetScale, omega: speed.omega, dt: dt)
                x.step(toward: spot.x, omega: speed.omega, dt: dt)
                y.step(toward: spot.y, omega: speed.omega, dt: dt)
            } else if targetScale > 1 {
                // A zoom from the very first frame starts zoomed in.
                scale = Spring(value: targetScale); x = Spring(value: spot.x); y = Spring(value: spot.y)
            }
            samples.append(Sample(scale: scale.value, x: x.value, y: y.value))
        }
        self.samples = samples
    }

    /// Share of what shows, around its middle, that the cursor can move in
    /// without moving the camera.
    public static let deadZone = 0.6

    /// The spot moved just enough that `pointer` is inside the dead zone of
    /// a view `scale` times bigger centered on `spot`.
    static func follow(_ pointer: CGPoint, from spot: CGPoint, scale: Double) -> CGPoint {
        let half = 0.5 / scale * deadZone
        func axis(_ p: Double, _ c: Double) -> Double { min(max(c, p - half), p + half) }
        return CGPoint(x: axis(pointer.x, spot.x), y: axis(pointer.y, spot.y))
    }

    /// The camera at source time `t`, between two samples on the line
    /// between them. `crop` maps the spot onto the part of the recording that shows.
    public func view(at t: Double, crop: CropRect = .full) -> ZoomView {
        guard !samples.isEmpty else { return .none }
        let f = min(max(t * Self.rate, 0), Double(samples.count - 1))
        let i = Int(f), j = min(i + 1, samples.count - 1), w = f - Double(i)
        let a = samples[i], b = samples[j]
        let scale = a.scale + (b.scale - a.scale) * w
        // Below a hundredth of a percent the camera is at rest.
        guard scale > 1.0001 else { return .none }
        let spot = crop.mapClamped(CGPoint(x: a.x + (b.x - a.x) * w, y: a.y + (b.y - a.y) * w))
        return ZoomTrack.view(scale: scale, x: spot.x, y: spot.y)
    }
}

/// A critically damped spring: the fastest way to a target with no
/// overshoot. `step` is the exact solution over `dt`, so it is stable at any
/// frame rate.
struct Spring: Sendable {
    var value: Double
    var velocity = 0.0

    mutating func step(toward target: Double, omega: Double, dt: Double) {
        let delta = value - target
        let temp = (velocity + omega * delta) * dt
        let decay = exp(-omega * dt)
        velocity = (velocity - omega * temp) * decay
        value = target + (delta + temp) * decay
    }
}
