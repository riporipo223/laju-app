import Foundation

/// Client-side point estimate — tech-spec.md §2.2-2.3. This is the
/// *client half* of the cross-language parity strategy in §2.2b: the
/// server (T2.6, TypeScript) is the sole source of truth for points that
/// actually get paid out; this function only produces the optimistic
/// local estimate shown before sync. It does not apply `trust_multiplier`
/// (server-side only, tied to anti-cheat history, §2.4) and assumes
/// clean input — no GPS/anti-cheat validation happens here, that's
/// T0.8's capture layer and the server's anti-cheat checks (T2.7-T2.10).
enum PointFormula {
    /// tech-spec.md §2.2. Starting value, not final — needs real-run-data
    /// tuning later, same status as the pace multiplier table below.
    static let streakBonusPerDay: Double = 2
    static let streakCapDays = 7

    /// tech-spec.md §2.2 — fix for a real grinding exploit found on-device
    /// (2026-09-13): `streakBonus` is additive, not multiplicative against
    /// `distanceKm`, so a 0-distance run (tap Start, immediately Stop)
    /// still earned full streak-bonus points (confirmed on-device: 6.0 and
    /// 8.0 points from `distanceMeters=0` runs, matching
    /// `min(streakDays,7) * streakBonusPerDay` exactly for streakDays 3
    /// and 4). Below this threshold, total points — base **and** streak
    /// bonus together — are zero, not just base. 0.1km (100m) is
    /// deliberately 5x `RunViewModel.stationaryRadiusMeters` (20m) so no
    /// GPS noise/jitter alone can cross it — same status as
    /// `streakBonusPerDay`/the pace table: a starting value, not final.
    static let minDistanceKmForPoints: Double = 0.1

    /// tech-spec.md §2.3 — half-open brackets `[lower, upper)` on
    /// `avgPaceSecPerKm`, so no pace value matches two brackets at once.
    static func paceMultiplier(avgPaceSecPerKm: Double) -> Double {
        switch avgPaceSecPerKm {
        case ..<180: 0.5 // < 3:00/km
        case 180 ..< 240: 1.2 // [3:00, 4:00)
        case 240 ..< 420: 1.0 // [4:00, 7:00)
        case 420 ..< 600: 0.9 // [7:00, 10:00)
        default: 0.7 // >= 10:00/km
        }
    }

    static func calculatePoints(distanceKm: Double, avgPaceSecPerKm: Double, streakDays: Int) -> Double {
        guard distanceKm >= minDistanceKmForPoints else { return 0 }
        let multiplier = paceMultiplier(avgPaceSecPerKm: avgPaceSecPerKm)
        let basePoints = distanceKm * multiplier
        let cappedStreakDays = min(streakDays, streakCapDays)
        let streakBonus = Double(cappedStreakDays) * streakBonusPerDay
        return basePoints + streakBonus
    }
}
