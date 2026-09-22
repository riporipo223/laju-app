import Foundation

/// T3.9: wire type for `GET /api/seasons/active` (database-api-spec.md §2.5, T2.17). `days_remaining` is
/// server-computed at response time — the client does not recompute it from `endAt`, so the countdown shown
/// right after load matches the server exactly; between loads the view ticks it down locally from `endAt`.
struct ActiveSeasonResponse: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let startAt: Date
    let endAt: Date
    let status: String
    let daysRemaining: Int
    /// Additive (T3.7a): the caller's own season points and league. `nil` when the caller has no profile yet
    /// or the points read fails — not an error, same contract as `LeaderboardResponse.me`.
    let me: ActiveSeasonMe?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case startAt = "start_at"
        case endAt = "end_at"
        case status
        case daysRemaining = "days_remaining"
        case me
    }
}

struct ActiveSeasonMe: Decodable, Sendable, Equatable {
    let seasonPoints: Int
    let league: String

    enum CodingKeys: String, CodingKey {
        case seasonPoints = "season_points"
        case league
    }
}
