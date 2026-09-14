import Foundation

/// T1.12: cumulative elevation gain/loss from a completed run's `gpsRoute` — product-spec.md §4.12. Pure
/// function, computed once at `RunViewModel.stop()` from every persisted point (drift/anchor-suppressed points
/// included, tech-spec.md §2.1b) — a stationary period's altitude jitter is exactly the kind of noise
/// `noiseFloorMeters` already filters, so no separate point-exclusion is needed on top of it.
enum ElevationTracker {
    /// Minimum altitude change trusted as real, not raw GPS altitude noise — phone GPS altitude commonly
    /// jitters several meters even standing still (no barometric fusion assumed). Mirrors `RunViewModel`'s
    /// `stationaryAnchor` pattern: the reference point only moves once a change clears this floor, so noise
    /// under it neither counts nor drifts the reference.
    static let noiseFloorMeters: Double = 3

    static func compute(points: [GPSPoint]) -> (gainMeters: Double, lossMeters: Double) {
        guard var reference = points.first?.elevation else { return (0, 0) }
        var gain = 0.0
        var loss = 0.0

        for point in points.dropFirst() {
            let delta = point.elevation - reference
            if delta >= noiseFloorMeters {
                gain += delta
                reference = point.elevation
            } else if delta <= -noiseFloorMeters {
                loss += -delta
                reference = point.elevation
            }
        }
        return (gain, loss)
    }
}
