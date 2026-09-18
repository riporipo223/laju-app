import Foundation

/// T2.14: wire types for `POST /api/runs` (database-api-spec.md §2.2) — snake_case `CodingKeys` matching
/// the backend exactly (backend/app/api/runs/route.ts). Kept separate from `GPSPoint`/`Run` (the local Core
/// Data model): those use the app's own default `JSONEncoder`/`JSONDecoder` conventions for local storage
/// round-tripping (`.deferredToDate`), which is NOT the wire format the server expects — this file's
/// encoder/decoder (below) are configured for ISO 8601 specifically for that reason.
struct SubmitRunRequest: Encodable {
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let durationSeconds: Double
    let gpsRoute: [GPSPoint]

    enum CodingKeys: String, CodingKey {
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case distanceMeters = "distance_meters"
        case durationSeconds = "duration_seconds"
        case gpsRoute = "gps_route"
    }
}

struct SubmitRunResponse: Decodable, Sendable {
    let runId: String
    let status: String
    let flagConfidence: String?
    let finalPointsAwarded: Double
    let resolvedAt: Date?
    let anomalyFlags: [String]

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case flagConfidence = "flag_confidence"
        case finalPointsAwarded = "final_points_awarded"
        case resolvedAt = "resolved_at"
        case anomalyFlags = "anomaly_flags"
    }
}

enum RunSubmissionCoding {
    /// Server accepts plain ISO 8601 (no fractional seconds) fine for request timestamps — `new Date(...)`
    /// on the backend side parses either form, so the simpler, standard strategy is sufficient here.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// The server's own JSON responses (`resolved_at`) DO include fractional seconds (e.g.
    /// `"2026-09-18T04:26:30.381Z"`, confirmed live against the deployed API) — Foundation's built-in
    /// `.iso8601` strategy cannot parse that form, so this tries fractional-seconds first, then falls back
    /// to the plain form, rather than silently failing to decode a real, common response shape.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Formatters are created fresh inside the closure rather than captured from the enclosing scope —
        // `ISO8601DateFormatter` isn't `Sendable`, and `dateDecodingStrategy`'s closure is `@Sendable`
        // (Swift 6 strict concurrency); a local instance created inside the closure body is not a capture.
        decoder.dateDecodingStrategy = .custom { dateDecoder in
            let container = try dateDecoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: dateString) {
                return date
            }

            let withoutFractional = ISO8601DateFormatter()
            withoutFractional.formatOptions = [.withInternetDateTime]
            if let date = withoutFractional.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(dateString)"
            )
        }
        return decoder
    }
}
