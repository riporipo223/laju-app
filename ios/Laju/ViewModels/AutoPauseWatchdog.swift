import Combine
import Foundation

/// T1.11: owns the auto-pause watchdog timer and "time since last confirmed movement" state — extracted from
/// `RunViewModel` purely to keep that type's body under SwiftLint's length limit (genuinely separable: only
/// needs a callback and a timestamp comparison, not any of `RunViewModel`'s other state).
final class AutoPauseWatchdog {
    private var timerCancellable: AnyCancellable?
    private(set) var lastConfirmedMovementAt: Date?

    /// Found 2026-09-15 (false-trigger report, on-device): a fix can arrive — proving the phone is receiving
    /// GPS updates at all — without being trustworthy enough to confirm real movement (`RunViewModel`'s
    /// `anchorAccuracyThresholdMeters` gate, tighter than `LocationTrackingService`'s own accept filter). The
    /// watchdog previously had no visibility into that case at all: a sustained run of accuracy-degraded-but-
    /// still-arriving fixes (locked screen, urban canyon) read as indistinguishable from genuine silence, and
    /// auto-paused a user who never stopped moving. Kept separate from `lastConfirmedMovementAt` — that field's
    /// literal meaning ("last confirmed movement") is still relied on by `RunViewModel`'s resume-seed path
    /// (T1.14), which must not be told "movement" happened when it didn't.
    private var lastDegradedSignalFixAt: Date?

    private var effectiveReferenceDate: Date? {
        [lastConfirmedMovementAt, lastDegradedSignalFixAt].compactMap(\.self).max()
    }

    /// Periodic (not fix-reactive — Round 7 B7-3, a stationary device gets almost no fixes to react to). 1s
    /// ticks so it's responsive and so tests can inject a short `thresholdSeconds` without waiting 60s real.
    func start(thresholdSeconds: TimeInterval = AutoPauseThreshold.seconds, onThresholdExceeded: @escaping () -> Void) {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if AutoPauseThreshold.isExceeded(
                    lastConfirmedMovementAt: effectiveReferenceDate,
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

    /// Call whenever a fix arrives that couldn't be trusted enough to confirm real movement (poor accuracy) —
    /// resets the pause clock without touching `stationaryAnchor`/`distanceMeters`, so a signal-degraded but
    /// still-moving run doesn't get auto-paused just because recent fixes were too noisy to count as confirmed
    /// movement. Does NOT imply movement happened — only that we can't yet tell either way.
    func deferPauseForDegradedSignal() {
        lastDegradedSignalFixAt = Date()
    }

    /// Seeds/clears the reference — `start()`/`resumeRecoveredRun(_:)` (T1.14) and manual `resume()` (a fresh
    /// grace window, since GPS was fully stopped during any pause).
    func reset(lastConfirmedMovementAt: Date?) {
        self.lastConfirmedMovementAt = lastConfirmedMovementAt
        lastDegradedSignalFixAt = nil
    }
}
