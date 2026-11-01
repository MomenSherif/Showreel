import Foundation

/// The mic's input level for the Record Panel's meter (S-004). It changes
/// 15 times a second, so it lives apart from `RecordController`: only the
/// views that show the level observe it.
@Observable
final class MicMeter {
    /// 0 (silent) to 1 (full scale).
    private(set) var level: Double = 0
    /// True after 5 seconds of near silence.
    private(set) var silent = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var silentSince: Date?
    @ObservationIgnored private var read: (() -> Float)?

    var isRunning: Bool { timer != nil }

    /// Polls `reading` (dBFS, about -60 to 0) at 15 Hz.
    func start(reading: @escaping () -> Float) {
        read = reading
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        read = nil
        level = 0
        silent = false
        silentSince = nil
    }

    private func tick() {
        guard let read else { return }
        level = max(0, min(1, (Double(read()) + 60) / 60))
        if level < 0.05 {
            if silentSince == nil { silentSince = .now }
            let quiet = Date.now.timeIntervalSince(silentSince ?? .now) > 5
            if quiet != silent { silent = quiet }
        } else {
            silentSince = nil
            if silent { silent = false }
        }
    }
}
