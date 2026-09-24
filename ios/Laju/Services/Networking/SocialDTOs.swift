import Foundation

/// T4.15: wire types for the Social Feed endpoints (`backend/app/api/social/posts`). The migration creating
/// `social_post`/`social_post_like` is written but NOT applied to production yet
/// (`20260924220000_social_feed_schema.sql`) — every call here fails against the live database until it is,
/// the same situation `ClubWarDTOs.swift` documented for T4.2c.
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
        case createdAt = "created_at"
        case likeCount = "like_count"
        case likedByCaller = "liked_by_caller"
    }
}

struct CreateSocialPostRequest: Encodable, Sendable {
    let runId: String
    let caption: String?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case caption
    }
}

struct CreateSocialPostResponse: Decodable, Sendable, Equatable {
    let postId: String
    let runId: String
    let caption: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case runId = "run_id"
        case caption
        case createdAt = "created_at"
    }
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
