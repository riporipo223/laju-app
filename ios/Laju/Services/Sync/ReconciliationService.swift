import CoreData
import Foundation

/// T2.14d: drives T2.14c's `GET /api/runs?since=` from the client — tech-spec.md §3 step 7. Learns about a
/// `flagged` run's *later* resolution (LOW auto-resolve, HIGH manual override) and mirrors it into the
/// local `Run` row, then tells the profile screen to re-fetch (`onRunsChanged` → `ProgressViewModel.refresh()`).
///
/// Deliberately separate from `SyncService` (T2.14's upload queue): a failure here never touches
/// `Run.syncStatus`, and this service never retries uploads.
///
/// `@MainActor`, same precedent as `SyncService`/`ProgressViewModel` — every Core Data access stays on
/// `viewContext`.
@MainActor
final class ReconciliationService {
    /// Flat cadence floor between *attempts* (success or failure), persisted in `SyncMeta` so it survives
    /// app restarts. No backoff beyond this — polling an indefinitely-`flagged` HIGH run forever is deliberate.
    static let minimumAttemptInterval: TimeInterval = 15 * 60

    private let persistence: PersistenceController
    private let apiClient: APIClient
    private let currentJWT: @Sendable () async throws -> String
    /// A `Run` save alone re-renders that run's own row via `@FetchRequest`, but does NOT re-fetch
    /// server-derived points/level — this explicit hook does (T2.16's `ProgressViewModel.refresh()`).
    private let onRunsChanged: @MainActor () async -> Void
    private let now: @Sendable () -> Date
    private var isReconciling = false

    init(
        persistence: PersistenceController,
        apiClient: APIClient = APIClient(),
        currentJWT: @escaping @Sendable () async throws -> String = {
            try await SupabaseConfig.client.auth.session.accessToken
        },
        onRunsChanged: @escaping @MainActor () async -> Void,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.persistence = persistence
        self.apiClient = apiClient
        self.currentJWT = currentJWT
        self.onRunsChanged = onRunsChanged
        self.now = now
    }

    func reconcileIfNeeded() async {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        let context = persistence.container.viewContext
        guard hasFlaggedRun(in: context) else { return }

        let meta = persistence.syncMeta(in: context)
        let current = now()
        guard isDue(meta: meta, now: current) else { return }

        let jwt: String
        do {
            jwt = try await currentJWT()
        } catch {
            return // signed out — not an attempt, retry on the next trigger.
        }

        meta.lastReconcileAttemptAt = current
        try? context.save()

        var didChangeAnyRun = false
        do {
            didChangeAnyRun = try await drain(meta: meta, jwt: jwt, context: context)
        } catch {
            // Attempt timestamp already stored; `lastReconciledAt` untouched, so the next attempt re-covers
            // the same window. Never enters T2.14's upload-retry queue.
        }

        if didChangeAnyRun {
            await onRunsChanged()
        }
    }

    private func isDue(meta: SyncMeta, now current: Date) -> Bool {
        guard let lastAttempt = meta.lastReconcileAttemptAt else { return true }
        let elapsed = current.timeIntervalSince(lastAttempt)
        // A negative `elapsed` means the device clock moved backwards past the stored attempt — treat
        // as due rather than blocking until the clock catches up.
        return elapsed < 0 || elapsed >= Self.minimumAttemptInterval
    }

    /// Calls the endpoint until the window is drained. Returns whether any local row changed.
    private func drain(meta: SyncMeta, jwt: String, context: NSManagedObjectContext) async throws -> Bool {
        var didChangeAnyRun = false
        while true {
            let cursor = meta.lastReconciledAt
            let response = try await apiClient.fetchRunStatuses(since: cursor, jwt: jwt)
            if await apply(response.runs, in: context, jwt: jwt) {
                didChangeAnyRun = true
            }

            guard response.hasMore else {
                // Window fully drained — the *server's* clock is the next cursor, never the device's.
                meta.lastReconciledAt = response.serverTime
                try? context.save()
                break
            }
            // Not drained: persisting `serverTime` here would skip everything still undrained if the
            // app dies mid-drain, so advance only to the last row actually received.
            guard let lastUpdatedAt = response.runs.last?.updatedAt else { break }
            // Termination guard (database-api-spec.md §2.2b): the filter is inclusive, so ≥200 rows
            // sharing one `updated_at` re-return the same boundary forever — stop when nothing is newer.
            if let cursor, lastUpdatedAt <= cursor {
                break
            }
            meta.lastReconciledAt = lastUpdatedAt
            try? context.save()
        }
        return didChangeAnyRun
    }

    private func hasFlaggedRun(in context: NSManagedObjectContext) -> Bool {
        let request = Run.fetchRequest()
        request.predicate = NSPredicate(format: "serverStatus == %@", "flagged")
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    /// Returns whether any matched local row's status or points actually changed. A `run_id` with no local
    /// match is ignored, never inserted.
    private func apply(_ runs: [ReconciledRun], in context: NSManagedObjectContext, jwt: String) async -> Bool {
        var changed = false
        var toPublish: [Run] = []
        for reconciled in runs {
            let request = Run.fetchRequest()
            request.predicate = NSPredicate(format: "serverRunId == %@", reconciled.runId)
            request.fetchLimit = 1
            guard let local = try? context.fetch(request).first else { continue }

            let pointsChanged = reconciled.finalPointsAwarded != nil
                && local.finalPointsAwarded?.doubleValue != reconciled.finalPointsAwarded
            if local.serverStatus != reconciled.status || pointsChanged {
                changed = true
            }
            local.serverStatus = reconciled.status
            local.flagConfidence = reconciled.flagConfidence
            if let points = reconciled.finalPointsAwarded {
                local.finalPointsAwarded = NSNumber(value: points)
            }
            local.anomalyFlags = try? JSONEncoder().encode(reconciled.anomalyFlags)
            local.resolvedAt = reconciled.resolvedAt
            toPublish.append(local)
        }
        try? context.save()
        // T4.21: a flagged run's later resolution to validated/approved is exactly the case
        // `SyncService`'s own publish call (fired right after the *initial* submit) can't cover —
        // that initial status might still be "flagged" at that point.
        for run in toPublish {
            await PendingPostPublisher.publishIfNeeded(for: run, apiClient: apiClient, jwt: jwt)
        }
        return changed
    }
}
