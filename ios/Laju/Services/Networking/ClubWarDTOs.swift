import Foundation

/// T4.2c: wire types for the Club War endpoints (backend `lib/club-war/http.ts` `serializeWar`, T4.2b).
/// The backend is written but its tables don't exist until T4.2a's migration is applied, and the Premium
/// check always denies until T4.20 — so today these are only exercised by tests and previews.
struct ClubWarListResponse: Decodable, Sendable, Equatable {
    let clubId: String
    let wars: [ClubWar]

    enum CodingKeys: String, CodingKey {
        case clubId = "club_id"
        case wars
    }
}

struct ClubWar: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let status: String
    let challengeSentAt: Date
    let acceptDeadlineAt: Date
    let startedAt: Date?
    let endsAt: Date?
    let endedAt: Date?
    let winnerClubId: String?
    let winReason: String?
    let clubs: [ClubWarClub]

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case challengeSentAt = "challenge_sent_at"
        case acceptDeadlineAt = "accept_deadline_at"
        case startedAt = "started_at"
        case endsAt = "ends_at"
        case endedAt = "ended_at"
        case winnerClubId = "winner_club_id"
        case winReason = "win_reason"
        case clubs
    }
}

struct ClubWarClub: Decodable, Sendable, Equatable {
    let clubId: String
    let role: String
    let inviteStatus: String

    enum CodingKeys: String, CodingKey {
        case clubId = "club_id"
        case role
        case inviteStatus = "invite_status"
    }
}

struct ClubWarRecordResponse: Decodable, Sendable, Equatable {
    let clubId: String
    let wins: Int
    let losses: Int
    let netWins: Int

    enum CodingKeys: String, CodingKey {
        case clubId = "club_id"
        case wins
        case losses
        case netWins = "net_wins"
    }
}

struct CreateClubWarRequest: Encodable, Sendable {
    let invitedClubIds: [String]

    enum CodingKeys: String, CodingKey {
        case invitedClubIds = "invited_club_ids"
    }
}

struct RespondClubWarRequest: Encodable, Sendable {
    let accept: Bool
}

struct ClubWarStatusResponse: Decodable, Sendable, Equatable {
    let warId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case warId = "war_id"
        case status
    }
}
