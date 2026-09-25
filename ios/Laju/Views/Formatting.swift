import Foundation

/// tech-spec.md §2.1c: distance shown to the user is always km, never
/// raw meters — storage/calculation stay in meters, this is presentation
/// only. Applies to any *real* user-facing screen (T1.2's summary here);
/// `RunTrackingView`'s live meter readout is a deliberate exception (it's
/// a debug/verification screen, not final UI — see §2.1c).
enum DistanceFormatter {
    static func format(meters: Double) -> String {
        let km = meters / 1000
        if km < 10 {
            return String(format: "%.2f km", km)
        }
        return String(format: "%.1f km", km)
    }
}

/// Kept for `PointFormula`/anti-cheat and every DTO/Core Data field that stores pace
/// (`avgPaceSecPerKm`) — those calculations are untouched (2026-09-25 GPS/speed audit: no evidence
/// they're inaccurate, and server-side anti-cheat pace thresholds depend on this exact unit). Only
/// user-facing display was asked to change — see `SpeedFormatter` below, which every UI call site now
/// uses instead of this formatter's own `.format`.
enum PaceFormatter {
    /// `avgPaceSecPerKm` as `M:SS /km`. Not meaningful at zero distance
    /// (pace is undefined) — callers should guard that case separately.
    static func format(secPerKm: Double) -> String {
        let totalSeconds = Int(secPerKm.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}

/// T4.21+ (GPS/speed audit, 2026-09-25 v1 decision): user-facing display replaces pace (`M:SS /km`)
/// with speed (`km/h`) everywhere — the underlying stored/computed value stays `avgPaceSecPerKm`
/// (seconds per km) unchanged; this only converts it for display. `secPerKm == 0` (no distance yet)
/// returns `0.0 km/h`, not a divide-by-zero — same "not meaningful at zero distance" case
/// `PaceFormatter` already documents, just a defined value instead of undefined here since 0 km/h at
/// zero distance reads naturally, where `0:00 /km` would not.
enum SpeedFormatter {
    static func format(secPerKm: Double) -> String {
        guard secPerKm > 0 else { return "0.0 km/h" }
        let kmh = 3600 / secPerKm
        return String(format: "%.1f km/h", kmh)
    }
}

/// T1.12: elevation gain/loss are always shown in whole meters — sub-meter precision isn't meaningful given
/// `ElevationTracker.noiseFloorMeters` already floors changes at 3m.
enum ElevationFormatter {
    static func format(meters: Double) -> String {
        String(format: "%.0f m", meters)
    }
}

enum DurationFormatter {
    static func format(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
