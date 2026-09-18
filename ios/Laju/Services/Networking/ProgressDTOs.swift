import Foundation

/// T2.16: wire type for `GET /api/users/me/progress` (database-api-spec.md §2.3,
/// backend/app/api/users/me/progress/route.ts). No date fields, so a plain `JSONDecoder` is sufficient —
/// unlike `RunSubmissionDTOs.swift`'s custom ISO 8601 decoder.
struct ProgressResponse: Decodable, Sendable, Equatable {
    let totalPoints: Int
    let currentLevel: Int
    let pointsToNextLevel: Int
    let trustScore: Double

    enum CodingKeys: String, CodingKey {
        case totalPoints = "total_points"
        case currentLevel = "current_level"
        case pointsToNextLevel = "points_to_next_level"
        case trustScore = "trust_score"
    }
}
