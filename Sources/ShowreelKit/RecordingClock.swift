import Foundation

/// Maps host time (seconds) to recording time with pauses removed.
/// Every track and the event log use it, so they stay in sync after any
/// number of pauses.
public struct RecordingClock: Sendable, Equatable {
    /// A finished pause, in host seconds.
    public struct Pause: Sendable, Equatable {
        public var start: Double
        public var end: Double
    }

    public private(set) var start: Double?
    /// Every finished pause, oldest first. Kept, not summed, so a sample that
    /// is processed late still gets the time it was captured at.
    public private(set) var pauses: [Pause] = []
    public private(set) var pausedAt: Double?

    public var pausedTotal: Double { pauses.reduce(0) { $0 + $1.end - $1.start } }

    public init() {}

    public var isStarted: Bool { start != nil }
    public var isPaused: Bool { pausedAt != nil }

    public mutating func begin(at host: Double) {
        start = host
        pauses = []
        pausedAt = nil
    }

    public mutating func pause(at host: Double) {
        guard start != nil, pausedAt == nil else { return }
        pausedAt = host
    }

    public mutating func resume(at host: Double) {
        guard let pausedAt else { return }
        pauses.append(Pause(start: pausedAt, end: max(pausedAt, host)))
        self.pausedAt = nil
    }

    /// Recording time for a sample at `host`, or nil before the start or while paused.
    public func mediaTime(at host: Double) -> Double? {
        guard let start, host >= start else { return nil }
        if let pausedAt, host >= pausedAt { return nil }
        var pausedBefore = 0.0
        for pause in pauses {
            if host >= pause.end { pausedBefore += pause.end - pause.start }
            else if host >= pause.start { return nil }
        }
        return host - start - pausedBefore
    }

    /// The elapsed recording time shown in the Recording Controls.
    public func elapsed(at host: Double) -> Double {
        guard let start else { return 0 }
        let end = pausedAt ?? host
        return max(0, end - start - pausedTotal)
    }
}
