import Foundation

/// T2.16: fetches server-authoritative progress (`GET /api/users/me/progress`, T2.15) for `ProfileView`,
/// replacing Fase 1's local-only estimate. Owned at the app root (`LajuApp`, same precedent as
/// `SyncService`/`AuthService`) and injected via `.environmentObject` — not created locally inside
/// `ProfileView` — so `refresh()` is callable from outside the screen. That's a real requirement, not
/// speculative: T2.14d's reconciliation loop needs to trigger a refresh after a background status update
/// completes, independent of whether the Profile screen happens to be on screen at that moment.
///
/// `@MainActor`, matching `AuthService`/`SyncService`'s precedent for a new `@Published`-state service.
@MainActor
final class ProgressViewModel: ObservableObject {
    /// `nil` until the first successful fetch — the screen's offline fallback (local `Run` estimate) reads
    /// this as its signal to fall back, so a failed/never-attempted fetch must never fabricate a zero value.
    @Published private(set) var serverProgress: ProgressResponse?
    @Published private(set) var isLoading = false

    private let apiClient: APIClient
    /// Injected rather than always going through `SupabaseConfig.client.auth.session` directly — same
    /// testability seam `SyncService` uses, lets tests exercise "no session" without a real Supabase call.
    private let currentJWT: @Sendable () async throws -> String

    init(
        apiClient: APIClient = APIClient(),
        currentJWT: @escaping @Sendable () async throws -> String = {
            try await SupabaseConfig.client.auth.session.accessToken
        }
    ) {
        self.apiClient = apiClient
        self.currentJWT = currentJWT
    }

    /// Re-fetches server-derived progress. On any failure (offline, signed out, server error),
    /// `serverProgress` is left untouched — never cleared to `nil` and never replaced with a fabricated
    /// value — so a caller that already has a last-known-good value keeps showing it, and a caller that
    /// never had one keeps falling back to the local estimate. No broken/blank UI state either way.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let jwt = try await currentJWT()
            serverProgress = try await apiClient.fetchProgress(jwt: jwt)
        } catch {
            // Offline / signed out / server error — caller's fallback path handles this, not this method.
        }
    }
}
