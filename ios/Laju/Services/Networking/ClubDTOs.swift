import Foundation

/// T4.1 (Create Club only — join/leave/browse/member list are separate, unbuilt scope):
/// `backend/app/api/clubs/route.ts`. Premium-gated — every call currently answers 403 `not_premium`
/// (`lib/club/premium.ts`'s stub), by design, until T4.20 ships.
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
