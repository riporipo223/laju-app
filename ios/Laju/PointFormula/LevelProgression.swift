import Foundation

/// database-api-spec.md §1 — must match that table exactly, row for row.
/// Defined independently on each side (this is the Swift/client half,
/// T1.3; `backend/lib`, TypeScript, is T2.15) since client and server
/// can no longer share one literal module post-pivot. Small/static
/// enough that a fixture file (like tech-spec.md §2.2b's point-formula
/// one) is unnecessary — parity is a direct row-for-row unit test on
/// each side instead.
struct LevelThreshold: Equatable {
    let level: Int
    let pointsRequired: Double
    let title: String
}

enum LevelProgression {
    static let levelThresholds: [LevelThreshold] = [
        LevelThreshold(level: 1, pointsRequired: 0, title: "Pemula"),
        LevelThreshold(level: 2, pointsRequired: 100, title: "Rajin"),
        LevelThreshold(level: 3, pointsRequired: 300, title: "Konsisten"),
        LevelThreshold(level: 4, pointsRequired: 700, title: "Gigih"),
        LevelThreshold(level: 5, pointsRequired: 1500, title: "Veteran"),
        LevelThreshold(level: 6, pointsRequired: 3000, title: "Elit"),
        LevelThreshold(level: 7, pointsRequired: 6000, title: "Master"),
        LevelThreshold(level: 8, pointsRequired: 12000, title: "Legenda")
    ]

    /// Highest level whose `pointsRequired` <= `totalPoints`.
    /// `levelThresholds[0]` (level 1, 0 points required) always matches
    /// for any non-negative total, so the `??` fallback is unreachable
    /// in practice — kept only because `last(where:)` returns an
    /// Optional and negative input isn't a case worth crashing on.
    static func currentLevel(totalPoints: Double) -> LevelThreshold {
        levelThresholds.last(where: { $0.pointsRequired <= totalPoints }) ?? levelThresholds[0]
    }

    /// database-api-spec.md §1: next level's `points_required` minus
    /// `totalPoints`. 0 at the top level — v1 has no cap beyond level 8,
    /// a total that exceeds it just stays at level 8 until the table is
    /// extended.
    static func pointsToNextLevel(totalPoints: Double) -> Double {
        let current = currentLevel(totalPoints: totalPoints)
        guard let next = levelThresholds.first(where: { $0.level == current.level + 1 }) else {
            return 0
        }
        return next.pointsRequired - totalPoints
    }

    /// T2.16: the server (`GET /api/users/me/progress`) returns `current_level` as a bare `Int`, not a
    /// title — this looks up the title for that level number from the same parity-tested table, rather than
    /// re-deriving the level from `totalPoints` a second time.
    static func title(forLevel level: Int) -> String {
        levelThresholds.first(where: { $0.level == level })?.title ?? levelThresholds[0].title
    }
}
