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
            // T2.20a: a 429 means the whole account is over its limit, not that this run is bad — the rest of
            // the backlog would only be refused too (a device offline for weeks holds a 100+ run queue), so stop
            // the batch. Every run stays `pendingSync` and the next cycle retries.
            guard await sync(run, jwt: jwt) else { return }
        }
    }

    /// - Returns: `false` when the server answered `429` and the batch must stop, `true` otherwise.
    private func sync(_ run: Run, jwt: String) async -> Bool {
        guard let startedAt = run.startedAt, let endedAt = run.endedAt else { return true }
        let gpsRoute = GPSPoint.decodeRoute(from: run.gpsRoute)
        // An empty route would only ever produce a guaranteed 422 from the server (database-api-spec.md
        // §3) — skip the round-trip. A finished run's route can never grow, so this is permanent too:
        // take it out of the queue instead of re-examining it on every cycle forever.
        guard !gpsRoute.isEmpty else {
            markRejectedPermanently(run)
            return true
        }

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
            return true
        } catch {
            // T2.14 DoD: a *transient* failure (network, 5xx, 401, 409 region-not-set, …) must not drop the
            // run — `syncStatus` stays `pendingSync`, so it remains in the next cycle's query set.
            //
            // A *permanent* rejection is different: the server said this exact payload is invalid
            // (400 e.g. `distance_meters <= 0`, 413 too large, 422 bad route), and resending the same bytes
            // can only ever fail again. Retrying it forever costs a request per run per cycle (found in the
            // Fase 2 audit: 69 of the 127 runs on the test device were such runs). It leaves the *upload*
            // queue but stays in local history — nothing is deleted.
            if case let APIClientError.server(statusCode, _) = error {
                if Self.isPermanentRejection(statusCode) {
                    markRejectedPermanently(run)
                }
                if statusCode == Self.rateLimitedStatusCode {
                    return false
                }
            }
            return true
        }
    }

    /// `429 Too Many Requests` — T2.20a's per-user/per-IP limit. Recoverable, but it ends the current batch.
    static let rateLimitedStatusCode = 429

    /// Status codes meaning "this payload will never be accepted". Deliberately narrow: 401/403 (session),
    /// 409 (region not set yet — fixable by the user), 429 and 5xx (server/limits) are all recoverable.
    static func isPermanentRejection(_ statusCode: Int) -> Bool {
        statusCode == 400 || statusCode == 413 || statusCode == 422
    }

    /// `Run.syncStatus` value for a run the server rejected as invalid. Not `pendingSync`, so
    /// `syncPendingRuns()`'s query no longer returns it; the row itself is kept.
    static let rejectedPermanentlyStatus = "rejectedPermanent"

    private func markRejectedPermanently(_ run: Run) {
        run.syncStatus = Self.rejectedPermanentlyStatus
        try? context.save()
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
