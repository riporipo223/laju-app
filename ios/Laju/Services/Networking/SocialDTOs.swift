import Foundation

/// T4.15: wire types for the Social Feed endpoints (`backend/app/api/social/posts`) — migration applied and
/// verified live 2026-09-25 (phase-4-backlog.md). T4.21 (Save Activity) extends the create request/response
/// with title/description/private_notes/map_type/visibility/gear_id, backed by the `activity_detail` side
/// table (`20260925120000_activity_detail_and_gear_schema.sql`) — not yet applied to production, same
/// two-step gate.
struct SocialFeedResponse: Decodable, Sendable, Equatable {
    let posts: [SocialPost]
    let hasMore: Bool
    let nextBefore: Date?

    enum CodingKeys: String, CodingKey {
        case posts
        case hasMore = "has_more"
        case nextBefore = "next_before"
    }
}

/// `distanceMeters`/`durationSeconds`/`avgPaceSecPerKm`/`finalPointsAwarded` are optional because the API
/// reads them via a live join to `run` (no denormalized snapshot, see the migration's own scope note) — a
/// null there would mean the joined run row genuinely has no value for it, not that decoding should fail.
struct SocialPost: Decodable, Sendable, Equatable, Identifiable {
    let postId: String
    let userId: String
    let username: String?
    let displayName: String?
    let avatarURL: String?
    let runId: String
    let distanceMeters: Double?
    let durationSeconds: Double?
    let avgPaceSecPerKm: Double?
    let finalPointsAwarded: Double?
    let caption: String?
    /// T4.21: all optional — a pre-T4.21 post has none of these (backfilled with defaults, see the
    /// migration), a T4.21 post has whatever the author left filled in on Save Activity.
    let title: String?
    let description: String?
    let mapType: String?
    let gearId: String?
    let createdAt: Date
    /// `var`, not `let`: `SocialViewModel.toggleLike` mutates these two fields in place on an already-decoded
    /// row for an optimistic UI update, rather than reconstructing the whole struct.
    var likeCount: Int
    var likedByCaller: Bool

    var id: String { postId }

    /// Falls back to `username`, then a generic label — never a blank name (same reasoning as the backend's
    /// `coalesce(display_name, username)` used for `frozen_display_name`, database-api-spec.md §1).
    var authorName: String {
        displayName ?? username ?? "Pelari Laju"
    }

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case runId = "run_id"
        case distanceMeters = "distance_meters"
        case durationSeconds = "duration_seconds"
        case avgPaceSecPerKm = "avg_pace_sec_per_km"
        case finalPointsAwarded = "final_points_awarded"
        case caption
        case title
        case description
        case mapType = "map_type"
        case gearId = "gear_id"
        case createdAt = "created_at"
        case likeCount = "like_count"
        case likedByCaller = "liked_by_caller"
    }
}

/// T4.21: `mapType`/`visibility` default server-side to "standard"/"public" when omitted (backend
/// route.ts) — sent here only when Save Activity has a real value to send, same optional shape as
/// `caption` always had.
struct CreateSocialPostRequest: Codable, Sendable {
    let runId: String
    let caption: String?
    let title: String?
    let description: String?
    let privateNotes: String?
    let mapType: String?
    let visibility: String?
    let gearId: String?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case caption
        case title
        case description
        case privateNotes = "private_notes"
        case mapType = "map_type"
        case visibility
        case gearId = "gear_id"
    }
}

struct CreateSocialPostResponse: Decodable, Sendable, Equatable {
    let postId: String
    let runId: String
    let caption: String?
    let title: String?
    let description: String?
    let mapType: String?
    let visibility: String?
    let gearId: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case runId = "run_id"
        case caption
        case title
        case description
        case mapType = "map_type"
        case visibility
        case gearId = "gear_id"
        case createdAt = "created_at"
    }
}

/// T4.21: a shoe the user has added, either from the profile screen or Save Activity's inline "Add Gear".
struct Gear: Codable, Sendable, Equatable, Identifiable {
    let gearId: String
    let brand: String
    let model: String?
    let size: String?
    let createdAt: Date

    var id: String { gearId }

    /// e.g. "Nike AirMax 95" or just "Nike" when no model was given.
    var displayName: String {
        [brand, model].compactMap { $0 }.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case gearId = "gear_id"
        case brand
        case model
        case size
        case createdAt = "created_at"
    }
}

struct CreateGearRequest: Encodable, Sendable {
    let brand: String
    let model: String?
    let size: String?
}

struct GearListResponse: Decodable, Sendable, Equatable {
    let gear: [Gear]
}

struct DeleteSocialPostResponse: Decodable, Sendable, Equatable {
    let postId: String
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case deleted
    }
}

struct SocialLikeResponse: Decodable, Sendable, Equatable {
    let postId: String
    let liked: Bool
    let likeCount: Int

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case liked
        case likeCount = "like_count"
    }
}
