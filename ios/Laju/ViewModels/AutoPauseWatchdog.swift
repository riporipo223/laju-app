import Combine
import Foundation

/// T1.11: owns the auto-pause watchdog timer and "time since last confirmed movement" state — extracted from
/// `RunViewModel` purely to keep that type's body under SwiftLint's length limit (genuinely separable: only
/// needs a callback and a timestamp comparison, not any of `RunViewModel`'s other state).
final class AutoPauseWatchdog {
    private var timerCancellable: AnyCancellable?
    private(set) var lastConfirmedMovementAt: Date?

    /// Periodic (not fix-reactive — Round 7 B7-3, a stationary device gets almost no fixes to react to). 1s
    /// ticks so it's responsive and so tests can inject a short `thresholdSeconds` without waiting 60s real.
    func start(thresholdSeconds: TimeInterval = AutoPauseThreshold.seconds, onThresholdExceeded: @escaping () -> Void) {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if AutoPauseThreshold.isExceeded(
                    lastConfirmedMovementAt: lastConfirmedMovementAt,
                    thresholdSeconds: thresholdSeconds
                ) {
                    onThresholdExceeded()
                }
            }
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    /// Call whenever `RunViewModel.stationaryAnchor` is established/moved — a real confirmed movement.
    func confirmMovement() {
        lastConfirmedMovementAt = Date()
    }

    /// Seeds/clears the reference — `start()`/`resumeRecoveredRun(_:)` (T1.14) and manual `resume()` (a fresh
    /// grace window, since GPS was fully stopped during any pause).
    func reset(lastConfirmedMovementAt: Date?) {
        self.lastConfirmedMovementAt = lastConfirmedMovementAt
    }
}
