import Foundation

/// T1.10: incremental per-km split tracking (product-spec.md §4.10),
/// extracted from `RunViewModel` into its own type purely to keep that
/// file under SwiftLint's file-length limit — genuinely a separable
/// concern (it only needs distance/duration snapshots, not any of
/// `RunViewModel`'s other state) rather than an arbitrary split.
///
/// Fed live, incremental `distanceMeters`/active-duration snapshots by
/// `RunViewModel` at the exact same site those values are computed — a
/// split's distance therefore always partitions the caller's own
/// `distanceMeters` exactly (product-spec §4.10 AC3), and a split
/// spanning a pause automatically excludes the paused time, since the
/// active-duration value passed in already excludes it (no separate
/// timestamp-gap heuristic needed).
final class SplitTracker {
    private(set) var splits: [RunSplit] = []
    private var lastBoundaryDistanceMeters: Double = 0
    private var lastBoundaryActiveDuration: TimeInterval = 0

    /// T1.14 (crash recovery): defaulted params let a resumed run seed
    /// the boundary at its already-persisted distance/duration instead
    /// of 0 — otherwise the next update would immediately misread the
    /// whole pre-crash distance as one giant "split". Splits from BEFORE
    /// the crash are still unrecoverable either way (never persisted,
    /// see `RunViewModel`'s own `splitTracker` doc) — this only prevents
    /// a wrong split, it doesn't resurrect the lost ones.
    func reset(distanceMeters: Double = 0, activeDuration: TimeInterval = 0) {
        splits = []
        lastBoundaryDistanceMeters = distanceMeters
        lastBoundaryActiveDuration = activeDuration
    }

    /// Call on every distance update — closes the current split once
    /// accumulated distance since the last boundary reaches 1000m.
    func recordDistanceUpdate(totalDistanceMeters: Double, totalActiveDuration: TimeInterval) {
        let distanceSinceBoundary = totalDistanceMeters - lastBoundaryDistanceMeters
        guard distanceSinceBoundary >= 1000 else { return }

        splits.append(RunSplit(
            splitNumber: splits.count + 1,
            distanceMeters: distanceSinceBoundary,
            durationSeconds: totalActiveDuration - lastBoundaryActiveDuration,
            isPartial: false
        ))
        lastBoundaryDistanceMeters = totalDistanceMeters
        lastBoundaryActiveDuration = totalActiveDuration
    }

    /// Call once at Stop — closes the trailing partial split (product-spec
    /// §4.10 AC2) if any distance accumulated since the last boundary.
    func finalizePartialSplit(totalDistanceMeters: Double, totalActiveDuration: TimeInterval) {
        guard totalDistanceMeters > lastBoundaryDistanceMeters else { return }
        splits.append(RunSplit(
            splitNumber: splits.count + 1,
            distanceMeters: totalDistanceMeters - lastBoundaryDistanceMeters,
            durationSeconds: totalActiveDuration - lastBoundaryActiveDuration,
            isPartial: true
        ))
    }
}
