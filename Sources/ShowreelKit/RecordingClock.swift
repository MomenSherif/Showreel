import Foundation

/// Maps host time (seconds) to recording time with pauses removed.
/// Every track and the event log use it, so they stay in sync after any
/// number of pauses.
public struct RecordingClock: Sendable, Equatable {
    public private(set) var start: Double?
    public private(set) var pausedTotal: Double = 0
    public private(set) var pausedAt: Double?

    public init() {}

    public var isStarted: Bool { start != nil }
    public var isPaused: Bool { pausedAt != nil }

    public mutating func begin(at host: Double) {
        start = host
        pausedTotal = 0
        pausedAt = nil
    }

    public mutating func pause(at host: Double) {
        guard start != nil, pausedAt == nil else { return }
        pausedAt = host
    }

    public mutating func resume(at host: Double) {
        guard let pausedAt else { return }
        pausedTotal += max(0, host - pausedAt)
        self.pausedAt = nil
    }

    /// Recording time for a sample at `host`, or nil before the start or while paused.
    public func mediaTime(at host: Double) -> Double? {
        guard let start, host >= start else { return nil }
        if let pausedAt, host >= pausedAt { return nil }
        return host - start - pausedTotal
    }

    /// The elapsed recording time shown in the Recording Controls.
    public func elapsed(at host: Double) -> Double {
        guard let start else { return 0 }
        let end = pausedAt ?? host
        return max(0, end - start - pausedTotal)
    }
}
