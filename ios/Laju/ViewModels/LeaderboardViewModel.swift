import Foundation

/// T2.20 (AC 4.5.2): how to describe the board's age. The precompute runs every 15 minutes (T2.18), so an
/// age well past that means the job has stalled — say so rather than presenting stale data as current.
enum LeaderboardFreshness {
    /// Past this the board is older than a healthy 15-minute cycle (plus slack for the request itself).
    static let staleAfter: TimeInterval = 20 * 60

    static func isStale(computedAt: Date?, now: Date) -> Bool {
        guard let computedAt else { return false }
        return now.timeIntervalSince(computedAt) > staleAfter
    }

    static func text(computedAt: Date?, now: Date) -> String {
        guard let computedAt else { return "Leaderboard belum dihitung" }
        let age = max(0, now.timeIntervalSince(computedAt))
        let base = if age < 60 {
            "Diperbarui baru saja"
        } else if age < 3600 {
            "Diperbarui \(Int(age / 60)) menit lalu"
        } else {
            "Diperbarui \(Int(age / 3600)) jam lalu"
        }
        return isStale(computedAt: computedAt, now: now) ? base + " — data mungkin belum terbarui" : base
    }
}

/// T2.20: loads the global leaderboard for `LeaderboardView`. `@MainActor` like the other `@Published`
/// services (`SyncService`, `ProgressViewModel`).
@MainActor
final class LeaderboardViewModel: ObservableObject {
    /// Last successful response. Kept across a later failure so a flaky connection doesn't blank a board the
    /// user is already looking at; `nil` only until the first success.
    @Published private(set) var response: LeaderboardResponse?
    @Published private(set) var isLoading = false
    /// Set on a failed load, cleared on the next success.
    @Published private(set) var loadFailed = false

    private let apiClient: APIClient
    private let currentJWT: @Sendable () async throws -> String
    /// Top N requested from the server. The caller's own rank arrives separately as `me`, so it is shown even
    /// when they are outside this window (AC 4.5.1).
    private let limit: Int

    init(
        apiClient: APIClient = APIClient(),
        currentJWT: @escaping @Sendable () async throws -> String = {
            try await SupabaseConfig.client.auth.session.accessToken
        },
        limit: Int = 50
    ) {
        self.apiClient = apiClient
        self.currentJWT = currentJWT
        self.limit = limit
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let jwt = try await currentJWT()
            response = try await apiClient.fetchLeaderboard(limit: limit, jwt: jwt)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}
