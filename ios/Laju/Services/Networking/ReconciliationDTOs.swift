import Foundation

/// T2.14d: wire types for `GET /api/runs?since=` (database-api-spec.md §2.2b, T2.14c).
struct ReconciliationResponse: Decodable, Sendable {
    let serverTime: Date
    let hasMore: Bool
    let runs: [ReconciledRun]

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case hasMore = "has_more"
        case runs
    }
}

struct ReconciledRun: Decodable, Sendable, Equatable {
    let runId: String
    let status: String
    let flagConfidence: String?
    /// Nullable in the DB (confirmed against the live endpoint) — a non-optional here would make one null row
    /// fail decoding of the whole page, and the same page would then fail forever.
    let finalPointsAwarded: Double?
    let resolvedAt: Date?
    let updatedAt: Date
    let anomalyFlags: [String]

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case flagConfidence = "flag_confidence"
        case finalPointsAwarded = "final_points_awarded"
        case resolvedAt = "resolved_at"
        case updatedAt = "updated_at"
        case anomalyFlags = "anomaly_flags"
    }
}

enum ReconciliationCoding {
    /// Cursor sent as `?since=` — fractional seconds kept so a millisecond-precision cursor is not rounded
    /// *forward* past a row (rounding down is harmless: the inclusive `>=` filter just re-returns it).
    static func sinceString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
