import CoreData
import CoreLocation
import Foundation

/// T1.14: crash/interrupt recovery (product-spec.md §4.14). A `Run` row
/// with no `endedAt` at app launch means the process was killed mid-run
/// (force-quit/crash) — `RunViewModel.stop()` never ran. This is a
/// standalone, stateless helper (not part of `RunViewModel`, which only
/// exists once a session is live) — it operates directly on Core Data at
/// launch, before any `RunViewModel` has been created.
enum RunRecovery {
    /// A run whose last activity is older than this isn't offered a
    /// Resume option — GPS context from that long ago is meaningless to
    /// reattach to (spec: "exact cutoff decided at implementation time").
    /// One real-world workout session is being resumed, not an abstract
    /// task; a day-old unfinished run is closed out instead.
    static let staleAfter: TimeInterval = 24 * 3600

    /// Call once at launch. Silently finalizes every unfinished run
    /// except the single most recent one — force-kills can happen more
    /// than once without ever being resolved, and any run older than the
    /// latest has already been superseded by the user starting again.
    /// Returns the run to prompt the user about (Resume vs Save as
    /// finished), or `nil` if nothing needs a decision (nothing
    /// unfinished, or the last one was too stale and got auto-finalized
    /// too).
    static func resolveOnLaunch(in context: NSManagedObjectContext) -> Run? {
        let unfinished = PersistenceController.unfinishedRuns(in: context)
        guard let mostRecent = unfinished.last else { return nil }
        for staleRun in unfinished.dropLast() {
            finalize(staleRun, in: context)
        }
        guard
            let startedAt = mostRecent.startedAt,
            Date().timeIntervalSince(startedAt) <= staleAfter
        else {
            finalize(mostRecent, in: context)
            return nil
        }
        return mostRecent
    }

    /// "Save as finished" (also used to auto-finalize superseded/stale
    /// runs above): closes the run at its LAST PERSISTED state, not
    /// "now" — `endedAt` is the last GPS fix's own timestamp (falling
    /// back to `startedAt` if not a single point was ever flushed), so
    /// the dead-app gap never counts as run time. `durationSeconds`/
    /// `distanceMeters` are used as-is from what was already
    /// incrementally persisted (T1.14's own duration-persistence fix,
    /// see `RunViewModel.periodicFlush()`), not recomputed from
    /// `gpsRoute` timestamps — that would double-count time already
    /// excluded by an explicit pause.
    @discardableResult
    static func finalize(_ run: Run, in context: NSManagedObjectContext) -> RunSummary {
        let route = GPSPoint.decodeRoute(from: run.gpsRoute)
        run.endedAt = route.last?.timestamp ?? run.startedAt ?? Date()

        let distanceKm = run.distanceMeters / 1000
        let avgPaceSecPerKm = distanceKm > 0 ? run.durationSeconds / distanceKm : 0
        let streakDays = streakDays(for: run, in: context)
        let estimatedPoints = PointFormula.calculatePoints(
            distanceKm: distanceKm,
            avgPaceSecPerKm: avgPaceSecPerKm,
            streakDays: streakDays
        )
        run.estimatedPoints = estimatedPoints
        try? context.save()
        let elevation = ElevationTracker.compute(points: route)

        return RunSummary(
            distanceMeters: run.distanceMeters,
            durationSeconds: run.durationSeconds,
            avgPaceSecPerKm: avgPaceSecPerKm,
            estimatedPoints: estimatedPoints,
            // A recovered run surfacing minutes/hours later isn't "the
            // moment" a level-up indicator (T1.3, AC 4.4.2) is for —
            // omitted deliberately, not forgotten.
            leveledUpTo: nil,
            streakDays: streakDays,
            routeCoordinates: route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) },
            // Pre-crash splits aren't recoverable — `SplitTracker` is
            // in-memory only (tech-spec.md §2.1b), lost with the process.
            splits: [],
            elevationGainMeters: elevation.gainMeters,
            elevationLossMeters: elevation.lossMeters
        )
    }

    private static func streakDays(for run: Run, in context: NSManagedObjectContext) -> Int {
        let priorStreakDays = PersistenceController.priorStreakDays(
            asOf: run.startedAt ?? Date(),
            in: context,
            excluding: run.id
        )
        let distanceKm = run.distanceMeters / 1000
        return distanceKm >= PointFormula.minDistanceKmForPoints ? priorStreakDays + 1 : priorStreakDays
    }
}
