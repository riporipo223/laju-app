import Foundation

/// T4.22 (product-spec.md §4.29): replicates the backend's severe-speed-violation rule
/// (`severe-speed-violation.ts`) client-side for a REAL-TIME advisory warning only — the server
/// remains the sole authority (ADR-0008), independently re-deriving the same outcome from
/// `gps_route` on sync. A modified client cannot bypass the actual point/penalty outcome by
/// suppressing or faking this detector's local state.
///
/// Same `speedCapKmh` (25) threshold as T2.8/the backend's own severe check — **not** the same
/// threshold as `LocationTrackingService`'s 12 m/s (43.2 km/h) raw-fix rejection filter
/// (tech-spec.md §2.1b) or the stationary-anchor jitter floor. Those two reject GPS noise before a
/// point ever reaches `RunViewModel`; this is a THIRD, later check with a different purpose — "is
/// this pace itself suspiciously fast for a human runner," not "is this fix GPS noise."
final class SevereSpeedViolationDetector {
    static let speedCapKmh: Double = 25
    static let consecutiveThreshold = 5
    static let windowSeconds: TimeInterval = 120

    private(set) var isTriggered = false
    private var streakTimestamps: [Date] = []

    /// Feed each newly-confirmed movement point's own instantaneous speed from the previous
    /// confirmed point (the same measurement `RunViewModel.handle(_:)`'s distance-from-anchor
    /// calculation already produces, just converted to km/h here for a shared threshold with the
    /// backend).
    func record(speedKmh: Double, at timestamp: Date) {
        if speedKmh > Self.speedCapKmh {
            streakTimestamps.append(timestamp)
            if streakTimestamps.count >= Self.consecutiveThreshold {
                let windowStart = streakTimestamps[streakTimestamps.count - Self.consecutiveThreshold]
                let windowEnd = streakTimestamps[streakTimestamps.count - 1]
                if windowEnd.timeIntervalSince(windowStart) <= Self.windowSeconds {
                    isTriggered = true
                }
            }
        } else {
            streakTimestamps = [] // AC2 — a clean sample resets the count to 0
        }
    }

    /// Called on a new run's Start/resume — same reset points `RunViewModel`'s own
    /// `recentMovementSamples` (CQ-11's rolling speed) uses, so a previous run's streak never
    /// leaks into a new one.
    func reset() {
        isTriggered = false
        streakTimestamps = []
    }
}
