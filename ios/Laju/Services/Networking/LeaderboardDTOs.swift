import Foundation

/// T2.20: wire types for `GET /api/leaderboard?scope=global` (database-api-spec.md §2.4, T2.19).
struct LeaderboardResponse: Decodable, Sendable, Equatable {
    let seasonId: String
    /// `nil` before the precompute job has ever run for the season.
    let computedAt: Date?
    let insufficientData: Bool
    let entries: [LeaderboardEntry]
    /// `nil` when the caller is not on the board — no counted points yet, or hidden for low trust. The two
    /// are deliberately indistinguishable to the client.
    let me: LeaderboardMe?

    enum CodingKeys: String, CodingKey {
        case seasonId = "season_id"
        case computedAt = "computed_at"
        case insufficientData = "insufficient_data"
        case entries
        case me
    }
}

struct LeaderboardEntry: Decodable, Sendable, Equatable, Identifiable {
    let rank: Int
    let userId: String
    /// The T2.18 `frozen_display_name` snapshot — can be `nil` for a user with neither display name nor username.
    let username: String?
    let points: Int

    var id: String {
        userId
    }

    enum CodingKeys: String, CodingKey {
        case rank
        case userId = "user_id"
        case username
        case points
    }
}

struct LeaderboardMe: Decodable, Sendable, Equatable {
    let rank: Int
    let points: Int
}
