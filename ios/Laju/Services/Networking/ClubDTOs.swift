import Foundation

/// T4.1: `backend/app/api/clubs/*`. Create Club is Premium-gated — every call currently answers 403
/// `not_premium` (`lib/club/premium.ts`'s stub), by design, until T4.20 ships. Browse/join/leave/member
/// list (T4.1b, added 2026-09-25) need no Premium check — any user can join a club, only creating one
/// needs it.
struct CreateClubRequest: Codable, Sendable {
    let name: String
    let description: String?
    let privacy: String

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case privacy
    }
}

struct CreateClubResponse: Decodable, Sendable, Equatable {
    let clubId: String
    let name: String
    let description: String?
    let privacy: String
    let inviteCode: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case clubId = "club_id"
        case name
        case description
        case privacy
        case inviteCode = "invite_code"
        case createdAt = "created_at"
    }
}

/// T4.1b: `GET /api/clubs` (browse) — deliberately has no `inviteCode` field, the endpoint never returns
/// it (leaking it would let anyone join an "invite-only" club without ever being given the code).
struct ClubSummary: Decodable, Sendable, Equatable, Identifiable {
    let clubId: String
    let name: String
    let description: String?
    let privacy: String
    let memberCount: Int
    let createdAt: Date

    var id: String { clubId }

    enum CodingKeys: String, CodingKey {
        case clubId = "club_id"
        case name
        case description
        case privacy
        case memberCount = "member_count"
        case createdAt = "created_at"
    }
}

struct ClubBrowseResponse: Decodable, Sendable, Equatable {
    let clubs: [ClubSummary]
    let hasMore: Bool
    let nextBefore: Date?

    enum CodingKeys: String, CodingKey {
        case clubs
        case hasMore = "has_more"
        case nextBefore = "next_before"
    }
}

struct ClubMember: Decodable, Sendable, Equatable, Identifiable {
    let userId: String
    let username: String?
    let displayName: String?
    let avatarURL: String?
    let role: String
    let joinedAt: Date

    var id: String { userId }

    var displayLabel: String {
        displayName ?? username ?? "Pelari Laju"
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case role
        case joinedAt = "joined_at"
    }
}

struct ClubMemberListResponse: Decodable, Sendable, Equatable {
    let members: [ClubMember]
}

struct JoinClubRequest: Encodable, Sendable {
    let inviteCode: String?

    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
    }
}

struct JoinClubResponse: Decodable, Sendable, Equatable {
    let clubId: String
    let joined: Bool

    enum CodingKeys: String, CodingKey {
        case clubId = "club_id"
        case joined
    }
}

struct LeaveClubResponse: Decodable, Sendable, Equatable {
    let clubId: String
    let left: Bool

    enum CodingKeys: String, CodingKey {
        case clubId = "club_id"
        case left
    }
}
