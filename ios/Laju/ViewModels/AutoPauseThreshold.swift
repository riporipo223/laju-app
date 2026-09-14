import Foundation

/// T1.11 (product-spec.md §4.11 AC1): pure time-threshold check backing the auto-pause watchdog timer in
/// `RunViewModel` — kept separate and pure so it's unit-testable without a real timer.
enum AutoPauseThreshold {
    /// No confirmed movement for at least a minute is treated as "stopped", not a brief check of a phone or a
    /// crosswalk glance — long enough to survive typical short stops without misfiring, short enough to still
    /// catch a genuine stop (waiting at a red light).
    static let seconds: TimeInterval = 60

    /// `lastConfirmedMovementAt` is `nil` until `RunViewModel`'s `stationaryAnchor` is first established — no
    /// anchor yet means no confirmed movement to measure from, so this never fires prematurely on GPS
    /// acquisition delay alone (product-spec §4.11 AC1: measures time since real movement, not since Start).
    static func isExceeded(
        lastConfirmedMovementAt: Date?,
        now: Date = Date(),
        thresholdSeconds: TimeInterval = seconds
    ) -> Bool {
        guard let lastConfirmedMovementAt else { return false }
        return now.timeIntervalSince(lastConfirmedMovementAt) >= thresholdSeconds
    }
}
