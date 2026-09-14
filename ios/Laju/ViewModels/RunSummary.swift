import CoreLocation
import Foundation

/// Snapshot handed to `RunSummaryView` (T1.2) when a run stops — a plain
/// value type, not the Core Data `Run` object itself, so the summary
/// screen has no dependency on `NSManagedObjectContext` lifetime.
struct RunSummary: Identifiable {
    let id = UUID()
    let distanceMeters: Double
    let durationSeconds: Double
    let avgPaceSecPerKm: Double
    let estimatedPoints: Double

    /// T1.3: non-nil only when this run's points pushed cumulative local
    /// points past a new level's threshold — `RunSummaryView` shows a
    /// level-up indicator when set (product-spec AC 4.4.2).
    let leveledUpTo: LevelThreshold?

    /// T1.4: consecutive-day run streak (including today) that produced
    /// this run's streak bonus — product-spec.md §3's "streak indicator"
    /// (Should-have, minimal: a number is enough).
    let streakDays: Int

    /// T1.9: the completed run's route, for the static map on
    /// `RunSummaryView` (product-spec.md §4.9 AC1) — reuses
    /// `RunViewModel`'s own live `routeCoordinates` (already built from
    /// the same points as `gpsRoute`, T1.8), not a re-decode of what was
    /// just persisted.
    let routeCoordinates: [CLLocationCoordinate2D]

    /// T1.10: per-km splits (product-spec.md §4.10), built live during
    /// the run — see `RunViewModel.finalizeSplitIfBoundaryCrossed()`.
    let splits: [RunSplit]

    /// T1.12: cumulative elevation gain/loss (product-spec.md §4.12) — `ElevationTracker.compute`, run once at
    /// `stop()` against the just-flushed `gpsRoute`.
    let elevationGainMeters: Double
    let elevationLossMeters: Double
}
