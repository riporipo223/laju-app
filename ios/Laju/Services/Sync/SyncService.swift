import CoreData
import Foundation

/// T2.14: pushes offline-recorded runs (`Run.syncStatus == "pendingSync"`) to `POST /api/runs` once
/// connectivity is available, retrying on failure. Covers only the *initial* status from the submission
/// response — a `flagged` run's later resolution is entirely T2.14d's job (via T2.14c's endpoint), not
/// this service's.
///
/// `@MainActor`, matching `AuthService`'s precedent (ios/Laju/Services/Auth/AuthService.swift) for a new
/// service with `@Published` state — also keeps every Core Data read/write on `viewContext`'s own thread
/// without introducing a background-context convention this codebase doesn't otherwise use. The `await`
/// on the network call still yields the main actor during I/O.
@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var isSyncing = false
    /// T2.14d: set once at app root to `ReconciliationService.reconcileIfNeeded` — kept as a plain hook so
    /// this upload queue never depends on (or is affected by) the reconciliation loop's failures.
    var onCycleFinished: (@MainActor () async -> Void)?

    private let context: NSManagedObjectContext
    private let apiClient: APIClient
    private let pathMonitor: PathMonitoring
    /// Injected rather than always going through `SupabaseConfig.client.auth.session` directly — lets
    /// tests exercise "no session" (signed out) without a real Supabase round-trip.
    private let currentJWT: @Sendable () async throws -> String

    init(
        context: NSManagedObjectContext,
        apiClient: APIClient = APIClient(),
        pathMonitor: PathMonitoring = NWPathMonitorAdapter(),
        currentJWT: @escaping @Sendable () async throws -> String = {
            try await SupabaseConfig.client.auth.session.accessToken
        }
    ) {
        self.context = context
        self.apiClient = apiClient
        self.pathMonitor = pathMonitor
        self.currentJWT = currentJWT

        pathMonitor.start { [weak self] isConnected in
            guard isConnected else { return }
            Task { @MainActor in
                await self?.syncPendingRuns()
            }
        }
    }

    /// `endedAt != nil` excludes still-in-progress runs (same predicate shape as
    /// `PersistenceController.unfinishedRuns`, inverted) — only a *finished* offline run is eligible to
    /// sync. Fetches every eligible run and attempts each in turn; one run's failure does not stop the
    /// others (only a missing/expired session aborts the whole batch, since no run can succeed without it).
    func syncPendingRuns() async {
        guard !isSyncing else { return }
        isSyncing = true
        await performSync()
        isSyncing = false
        // T2.14d: "on sync cycles" — runs after the upload pass regardless of its outcome; the hook applies
        // its own cadence floor and flagged-run precondition.
        await onCycleFinished?()
    }

    private func performSync() async {
        let request = Run.fetchRequest()
        request.predicate = NSPredicate(format: "syncStatus == %@ AND endedAt != nil", "pendingSync")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Run.startedAt, ascending: true)]
        guard let pendingRuns = try? context.fetch(request), !pendingRuns.isEmpty else { return }

        let jwt: String
        do {
            jwt = try await currentJWT()
        } catch {
            return // not signed in / session unavailable — retry on the next trigger, not a per-run failure.
        }

        for run in pendingRuns {
            await sync(run, jwt: jwt)
        }
    }

    private func sync(_ run: Run, jwt: String) async {
        guard let startedAt = run.startedAt, let endedAt = run.endedAt else { return }
        let gpsRoute = GPSPoint.decodeRoute(from: run.gpsRoute)
        // An empty route would only ever produce a guaranteed 422 from the server (database-api-spec.md
        // §3) — skip the wasted round-trip rather than burning a retry cycle on a request that can't
        // succeed. Leaves `syncStatus` as `pendingSync`, same as any other failure (see below).
        guard !gpsRoute.isEmpty else { return }

        let submission = SubmitRunRequest(
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: run.distanceMeters,
            durationSeconds: run.durationSeconds,
            gpsRoute: gpsRoute
        )

        do {
            let response = try await apiClient.submitRun(submission, jwt: jwt)
            apply(response, to: run)
            try? context.save()
        } catch {
            // T2.14 DoD: repeated failures must not drop the run — `syncStatus` is deliberately left
            // untouched (still `pendingSync`), so it remains in the next `syncPendingRuns()` call's query
            // set. No separate "failed" state is introduced; retry is simply "try again next trigger."
        }
    }

    private func apply(_ response: SubmitRunResponse, to run: Run) {
        run.syncStatus = "synced"
        run.serverRunId = response.runId
        run.serverStatus = response.status
        run.flagConfidence = response.flagConfidence
        run.finalPointsAwarded = NSNumber(value: response.finalPointsAwarded)
        run.resolvedAt = response.resolvedAt
        run.anomalyFlags = try? JSONEncoder().encode(response.anomalyFlags)
    }
}
