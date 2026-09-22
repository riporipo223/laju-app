import Foundation

/// T3.9 (product-spec AC 4.7.2): loads `GET /api/seasons/active` and keeps the countdown moving between
/// loads. The server's `daysRemaining` is authoritative right after a load; `liveDaysRemaining(now:)`
/// recomputes it locally from `endAt` so the screen does not need a fresh network call every tick to avoid
/// showing a stale number hours or days later.
@MainActor
final class SeasonInfoViewModel: ObservableObject {
    @Published private(set) var season: ActiveSeasonResponse?
    @Published private(set) var isLoading = false
    /// Set on a failed load, cleared on the next success — same contract as `LeaderboardViewModel.loadFailed`.
    @Published private(set) var loadFailed = false

    private let apiClient: APIClient
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

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let jwt = try await currentJWT()
            season = try await apiClient.fetchActiveSeason(jwt: jwt)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// Days remaining, recomputed from `endAt` against `now` rather than replayed from the load-time value —
    /// so a screen left open across the season's actual end still counts down correctly. Uses the same
    /// `ceil` rule as the server (database-api-spec.md §2.5) so the two never disagree.
    func liveDaysRemaining(now: Date) -> Int? {
        guard let endAt = season?.endAt else { return nil }
        let remainingDays = endAt.timeIntervalSince(now) / 86400
        return max(0, Int(remainingDays.rounded(.up)))
    }
}
