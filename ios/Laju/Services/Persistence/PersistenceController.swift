import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    /// Parsed exactly once per process and reused by every
    /// `PersistenceController` instance. Re-parsing `Laju.momd` on each
    /// `init` (the original bug: `NSPersistentContainer(name:)` re-derives
    /// a model each time) produces a distinct `NSManagedObjectModel`
    /// object per instance — Core Data's `+entity` resolution then sees
    /// multiple model objects claiming the same `Run`/`SyncMeta` classes
    /// and can't disambiguate, even though both came from the identical
    /// file. This bit when the test host app's own `.shared` and a test's
    /// `PersistenceController(inMemory: true)` both existed in the same
    /// process (found running LajuTests, T0.6 verification).
    /// `nonisolated(unsafe)`: `NSManagedObjectModel` is immutable once
    /// loaded and safe to share, but isn't `Sendable` so Swift 6 strict
    /// concurrency can't verify that itself — this documents the
    /// exception is deliberate, per the compiler's own suggested fix.
    private nonisolated(unsafe) static let model: NSManagedObjectModel = {
        guard
            let modelURL = Bundle(for: BundleToken.self).url(forResource: "Laju", withExtension: "momd"),
            let model = NSManagedObjectModel(contentsOf: modelURL)
        else {
            fatalError("Failed to locate Laju Core Data model")
        }
        return model
    }()

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Laju", managedObjectModel: Self.model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Unresolved Core Data error: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// `SyncMeta` is a single-instance entity — the reconciliation cursor
    /// and cadence anchor (tech-spec.md §3 step 7). Fetches the existing
    /// instance or creates it on first access.
    func syncMeta(in context: NSManagedObjectContext) -> SyncMeta {
        let request = SyncMeta.fetchRequest()
        request.fetchLimit = 1
        if let existing = try? context.fetch(request).first {
            return existing
        }
        let created = SyncMeta(context: context)
        try? context.save()
        return created
    }

    /// T1.3: cumulative local points — the input to level derivation
    /// (`LevelProgression`). Sum of `estimatedPoints` across every local
    /// `Run` row; product-spec.md §4.4 describes this as "synced+local"
    /// once a server exists (Fase 2), but nothing is synced yet, so all
    /// local runs are the whole story for now. A plain fetch-and-reduce,
    /// not a Core Data aggregate expression — Fase 1's run counts (a
    /// dozen-ish for internal dogfood, T1.17) don't need one.
    static func totalEstimatedPoints(in context: NSManagedObjectContext) -> Double {
        let request = Run.fetchRequest()
        let runs = (try? context.fetch(request)) ?? []
        return runs.reduce(0) { $0 + $1.estimatedPoints }
    }

    /// T1.4: local runs' `startedAt`, feeding `StreakTracker`'s
    /// consecutive-day computation — same reasoning as
    /// `totalEstimatedPoints` above, a plain fetch is enough at Fase 1's
    /// run counts. `minDistanceMeters` filters out non-qualifying runs
    /// (`PointFormula.minDistanceKmForPoints`, fixed 2026-09-13) — without
    /// this, a 0-distance tap-Start-tap-Stop run would count as "ran
    /// today" for every future day's streak calculation, letting someone
    /// keep a streak alive indefinitely with empty runs and cash it in
    /// later on one real run.
    /// `excluding` (T1.14, crash recovery): a run being finalized long
    /// after `start()` may already have real distance persisted on it —
    /// without excluding its own id, it would appear in its own "prior
    /// days" streak lookup and get double-counted (once as "prior", once
    /// via the +1 "this run qualifies" step). Not needed at `start()`
    /// itself — a run's own row still has `distanceMeters=0` at that
    /// point, so the `>=` predicate already excludes it for free.
    static func runStartDates(
        in context: NSManagedObjectContext,
        minDistanceMeters: Double,
        excluding excludedRunID: UUID? = nil
    ) -> [Date] {
        let request = Run.fetchRequest()
        var predicates = [NSPredicate(format: "distanceMeters >= %f", minDistanceMeters)]
        if let excludedRunID {
            predicates.append(NSPredicate(format: "id != %@", excludedRunID as CVarArg))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let runs = (try? context.fetch(request)) ?? []
        return runs.compactMap(\.startedAt)
    }

    /// T1.14: runs with no `endedAt` — either still genuinely active in
    /// this same process, or left over from a force-quit/crash in a
    /// PREVIOUS session (the case this task exists for). Sorted oldest
    /// first so the caller can treat `.last` as "the most recent one" —
    /// see `RunRecovery.resolveOnLaunch`.
    static func unfinishedRuns(in context: NSManagedObjectContext) -> [Run] {
        let request = Run.fetchRequest()
        request.predicate = NSPredicate(format: "endedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Run.startedAt, ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// Combines `runStartDates` + `StreakTracker.currentStreakDays` for "prior qualifying streak as of the
    /// day before `referenceDate`" — shared by `RunViewModel.beginTracking` (`start()`/resume) and
    /// `RunRecovery.finalize`, which both need this exact computation.
    static func priorStreakDays(
        asOf referenceDate: Date,
        in context: NSManagedObjectContext,
        excluding excludedRunID: UUID? = nil
    ) -> Int {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        return StreakTracker.currentStreakDays(
            asOf: yesterday,
            runDates: runStartDates(
                in: context,
                minDistanceMeters: PointFormula.minDistanceKmForPoints * 1000,
                excluding: excludedRunID
            )
        )
    }
}

/// Anchor type for `Bundle(for:)` — resolves to the app's own bundle
/// (where `Laju.momd` lives) regardless of which target/process is
/// hosting this code (app run vs. `LajuTests`).
private final class BundleToken {}
