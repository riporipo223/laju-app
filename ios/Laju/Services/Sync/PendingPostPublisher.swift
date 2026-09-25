import CoreData

/// T4.21: Save Activity's deferred-publish step. A run finished via Save Activity's "Save Activity
/// (Publish)" button carries `pendingPostRequested = true` plus the drafted title/description/private
/// notes/map type/visibility/gear id — but `POST /api/social/posts` requires a `validated`/`approved`
/// server-side run status, which is only known after the run has synced and (if flagged) been resolved.
/// Both `SyncService` (initial submit response) and `ReconciliationService` (later status resolution) call
/// this right after they set `serverStatus`, so the post fires automatically the moment the run qualifies —
/// the user never has to come back and manually post from Run History.
/// `@MainActor` — both callers (`SyncService`, `ReconciliationService`) are `@MainActor` themselves (every
/// Core Data access stays on the main actor, same precedent both document), so `Run` here must be too.
@MainActor
enum PendingPostPublisher {
    private static let publishableStatuses: Set<String> = ["validated", "approved"]

    /// No-ops (returns immediately, no network call) unless every precondition holds: a post was actually
    /// requested, it hasn't already been published, the run has a server id, and its status now qualifies.
    /// A network failure here is silently swallowed — `pendingPostRequested` stays `true` and
    /// `pendingPostPublished` stays `false`, so the next sync/reconciliation pass that observes a
    /// qualifying status retries; nothing here ever marks it published without a real 201 back.
    static func publishIfNeeded(for run: Run, apiClient: APIClient, jwt: String) async {
        guard run.pendingPostRequested, !run.pendingPostPublished else { return }
        guard let serverRunId = run.serverRunId else { return }
        guard let status = run.serverStatus, publishableStatuses.contains(status) else { return }

        do {
            _ = try await apiClient.createSocialPost(
                runId: serverRunId,
                caption: nil,
                title: run.pendingPostTitle,
                description: run.pendingPostDescription,
                privateNotes: run.pendingPostPrivateNotes,
                mapType: run.pendingPostMapType,
                visibility: run.pendingPostVisibility,
                gearId: run.pendingPostGearId,
                jwt: jwt
            )
            run.pendingPostPublished = true
            if let context = run.managedObjectContext {
                try? context.save()
            }
        } catch {
            // Swallowed deliberately — see the doc comment above.
        }
    }
}
