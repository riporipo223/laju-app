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

/// product-spec.md §4.24 AC23: kick-member, free for every tier — same `DELETE .../members` endpoint
/// `leaveClub` uses, distinguished server-side only by whether this body's `userId` is present.
struct KickMemberRequest: Encodable, Sendable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

struct KickMemberResponse: Decodable, Sendable, Equatable {
    let clubId: String
    let kickedUserId: String
    let kicked: Bool

    enum CodingKeys: String, CodingKey {
        case clubId = "club_id"
        case kickedUserId = "kicked_user_id"
        case kicked
    }
}

/// product-spec.md §4.24 AC13: Circle Challenge. `targetType` is `"distance"` or `"duration"` — unit
/// depends on it, matching the backend's own convention (meters/seconds), same as `Run`'s columns.
struct CreateChallengeRequest: Encodable, Sendable {
    let name: String
    let targetType: String
    let targetValue: Double
    let deadline: Date

    enum CodingKeys: String, CodingKey {
        case name
        case targetType = "target_type"
        case targetValue = "target_value"
        case deadline
    }
}

struct CreateChallengeResponse: Decodable, Sendable, Equatable {
    let challengeId: String
    let clubId: String
    let name: String
    let targetType: String
    let targetValue: Double
    let deadline: Date
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case clubId = "club_id"
        case name
        case targetType = "target_type"
        case targetValue = "target_value"
        case deadline
        case status
        case createdAt = "created_at"
    }
}

struct ChallengeRankingEntry: Decodable, Sendable, Equatable, Identifiable {
    let userId: String
    let total: Double

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case total
    }
}

/// `GET /api/clubs/[id]/challenge` — progress + individual ranking. Distinct from
/// `CreateChallengeResponse` (no `created_at`/`collective_total`/`ranking` overlap between the two
/// endpoints' shapes).
struct ChallengeProgressResponse: Decodable, Sendable, Equatable {
    let challengeId: String
    let clubId: String
    let name: String
    let targetType: String
    let targetValue: Double
    let deadline: Date
    let status: String
    let collectiveTotal: Double
    let ranking: [ChallengeRankingEntry]

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case clubId = "club_id"
        case name
        case targetType = "target_type"
        case targetValue = "target_value"
        case deadline
        case status
        case collectiveTotal = "collective_total"
        case ranking
    }
}

struct CancelChallengeResponse: Decodable, Sendable, Equatable {
    let challengeId: String
    let cancelled: Bool

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case cancelled
    }
}

struct ClubAnalyticsContributor: Decodable, Sendable, Equatable, Identifiable {
    let userId: String
    let distanceMeters: Double
    let points: Int

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case distanceMeters = "distance_meters"
        case points
    }
}

/// product-spec.md §4.24 AC12: rolling 30 days, top-5 ranked by distance (confirmed 2026-09-26, not
/// points — product-spec.md's own note on this).
struct ClubAnalyticsResponse: Decodable, Sendable, Equatable {
    let totalDistanceMeters: Double
    let totalPoints: Int
    let activeMemberCount: Int
    let topContributors: [ClubAnalyticsContributor]

    enum CodingKeys: String, CodingKey {
        case totalDistanceMeters = "total_distance_meters"
        case totalPoints = "total_points"
        case activeMemberCount = "active_member_count"
        case topContributors = "top_contributors"
    }
}
