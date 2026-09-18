import Foundation

/// T2.14b (product-spec AC 4.3.2): turns the locally-stored server outcome (`Run.serverStatus`,
/// `flagConfidence`, `anomalyFlags` — written by T2.14, kept current by T2.14d) into user-facing Indonesian
/// copy. Pure — no Core Data, no UI — so every status × confidence combination is unit-testable.
///
/// Raw flag codes (`gps_speed_jump_segment_3`) are never returned: every code maps to a plain-language
/// reason, and an unknown/future code falls back to a generic one rather than leaking the raw string.
struct RunStatusCopy: Equatable {
    let headline: String
    let reasons: [String]

    /// `nil` = nothing to say (not synced yet, or `validated` — a `validated` run whose points differ from the
    /// local estimate due to `trust_multiplier` is an explicitly out-of-scope gap, see T2.14b's scope).
    static func make(serverStatus: String?, flagConfidence: String?, anomalyFlags: [String]) -> RunStatusCopy? {
        let reasons = translate(anomalyFlags)
        switch serverStatus {
        case "flagged":
            let headline = flagConfidence == "high"
                ? "Poin ditahan, perlu direview manual, bisa makan waktu lebih lama"
                : "Poin tertahan sementara, otomatis diproses dalam ≤48 jam"
            return RunStatusCopy(headline: headline, reasons: reasons)
        case "approved":
            return RunStatusCopy(headline: "Poin kamu sudah disetujui dan masuk leaderboard", reasons: [])
        case "rejected":
            return RunStatusCopy(headline: "Poin dibatalkan", reasons: reasons)
        default:
            return nil
        }
    }

    /// Order-preserving, de-duplicated: five `gps_speed_jump_segment_N` flags read as one reason, not five.
    static func translate(_ flags: [String]) -> [String] {
        var seen = Set<String>()
        var messages: [String] = []
        for flag in flags {
            let message = message(for: flag)
            if seen.insert(message).inserted {
                messages.append(message)
            }
        }
        return messages
    }

    private static func message(for flag: String) -> String {
        if flag == "pace_cap_exceeded" {
            return "Pace rata-rata kamu terlalu cepat untuk lari manusia"
        }
        if flag.hasPrefix("gps_speed_jump_segment_") {
            return "Lari kamu kedeteksi lompat lokasi tiba-tiba"
        }
        if flag.hasPrefix("distance_duration_sanity_segment_") {
            return "Jarak dan waktu di sebagian rute tidak masuk akal"
        }
        if flag.hasPrefix("elevation_anomaly_segment_") {
            return "Perubahan ketinggian di rute kamu tidak wajar"
        }
        return "Ada pola lari yang tidak biasa"
    }
}

extension Run {
    /// Decodes the JSON-encoded `anomalyFlags` blob (written by `SyncService`/`ReconciliationService`).
    var statusCopy: RunStatusCopy? {
        let flags = (try? JSONDecoder().decode([String].self, from: anomalyFlags ?? Data())) ?? []
        return RunStatusCopy.make(serverStatus: serverStatus, flagConfidence: flagConfidence, anomalyFlags: flags)
    }
}
