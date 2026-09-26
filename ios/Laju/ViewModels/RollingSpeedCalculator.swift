import Foundation

/// CQ-11 fix (code-quality-audit.md): replaces the live speed's whole-run cumulative average
/// (root cause of on-screen jumpiness — see the audit entry) with a rolling window over only
/// recently confirmed GPS movement, recomputed fresh every UI tick (`RunTrackingView`'s
/// `TimelineView` already re-renders every second — no new timer needed).
///
/// `windowSeconds` is a STARTING value, not final — needs on-device tuning with real run data,
/// same status as `STREAK_BONUS_PER_DAY`/the pace-bracket table (tech-spec.md §2.2/§2.3). 30s is a
/// judgment call: short enough to feel "current," long enough to hold several GPS fixes at
/// `LocationTrackingService`'s 10m distanceFilter (a fix roughly every 3-4s at an easy running
/// pace), so a single point's jitter doesn't dominate the window.
enum RollingSpeedCalculator {
    struct MovementSample: Equatable {
        let timestamp: Date
        let distanceMeters: Double
    }

    static let defaultWindowSeconds: TimeInterval = 30
    /// Below this, the window's own elapsed span is too close to zero to divide by safely — return
    /// `nil` (caller shows a neutral placeholder) rather than a wildly inflated/deflated number.
    private static let minimumWindowSpanSeconds: TimeInterval = 5

    /// `nil` means "not enough recent data yet" — deliberately NOT a fallback to the cumulative
    /// average (that would just reintroduce this fix's own bug for the run's first few seconds).
    ///
    /// Each `MovementSample.distanceMeters` is the increment accumulated BETWEEN the previous
    /// confirmed GPS point and this one — so it was covered strictly BEFORE this sample's own
    /// timestamp, not during `[oldest, newest]`. The oldest sample in the window is therefore
    /// excluded from the distance sum (its own distance belongs to the span before it, which is
    /// outside this window) — only the elapsed time between it and the newest sample defines the
    /// window's span. Confirmed by `testExcludesSamplesOlderThanTheWindow` and the variance test:
    /// including it instead systematically overstates distance relative to elapsed time, understating
    /// (i.e. showing an artificially FASTER) pace early in the window's life.
    static func rollingPaceSecPerKm(
        samples: [MovementSample],
        windowSeconds: TimeInterval = defaultWindowSeconds,
        now: Date
    ) -> Double? {
        let windowStart = now.addingTimeInterval(-windowSeconds)
        let inWindow = samples
            .filter { $0.timestamp >= windowStart && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }
        guard inWindow.count >= 2, let oldest = inWindow.first?.timestamp, let newest = inWindow.last?.timestamp else { return nil }
        let elapsed = newest.timeIntervalSince(oldest)
        guard elapsed >= minimumWindowSpanSeconds else { return nil }
        let totalDistanceKm = inWindow.dropFirst().reduce(0.0) { $0 + $1.distanceMeters } / 1000
        guard totalDistanceKm > 0 else { return nil }
        return elapsed / totalDistanceKm
    }
}
