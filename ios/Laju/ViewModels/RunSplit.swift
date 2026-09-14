import Foundation

/// T1.10: one per-kilometer split (product-spec.md §4.10). Built
/// incrementally by `RunViewModel` at the exact moment `distanceMeters`
/// itself increases — not re-derived from persisted `gpsRoute` after the
/// fact, since the accepted-point stream (already filtered by
/// `stationaryAnchor`) and the active-duration mechanism (already pause-
/// exclusive) both already exist live during the run. A split's own
/// `distanceMeters` can be slightly over 1000 for a non-partial split —
/// GPS points arrive in discrete jumps, not continuously, so an exact
/// 1000.0 boundary is not guaranteed; the sum of every split's
/// `distanceMeters` (completed + partial) always equals the run's total
/// `distanceMeters` exactly, since splits simply partition the same
/// sequential distance additions into consecutive buckets.
struct RunSplit: Identifiable {
    let id = UUID()
    let splitNumber: Int
    let distanceMeters: Double
    let durationSeconds: TimeInterval
    let isPartial: Bool

    var avgPaceSecPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        return durationSeconds / (distanceMeters / 1000)
    }
}
