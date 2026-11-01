import CoreMedia
import Synchronization
import ShowreelKit

/// The recording clock shared by every track and the event log. Samples
/// carry host-clock times; the timeline turns them into recording time with
/// pauses removed, so all files line up (S-007).
public final class Timeline: Sendable {
    private let clock = Mutex(RecordingClock())

    public init() {}

    public static var hostNow: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    public func begin(at host: Double = Timeline.hostNow) { clock.withLock { $0.begin(at: host) } }
    public func pause(at host: Double = Timeline.hostNow) { clock.withLock { $0.pause(at: host) } }
    public func resume(at host: Double = Timeline.hostNow) { clock.withLock { $0.resume(at: host) } }
    public func mediaTime(at host: Double) -> Double? { clock.withLock { $0.mediaTime(at: host) } }
    public func elapsed(at host: Double = Timeline.hostNow) -> Double { clock.withLock { $0.elapsed(at: host) } }
    public var isStarted: Bool { clock.withLock { $0.isStarted } }
    public var isPaused: Bool { clock.withLock { $0.isPaused } }
}
