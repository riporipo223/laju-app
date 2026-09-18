/**
 * database-api-spec.md §1's "Level" table — a static lookup config, not a DB table (level is a pure
 * function of `User.total_points`). This module is created now because T2.12c's own DoD requires
 * `User.current_level` to be computed correctly after a ledger write, but the table's formal "owner" with
 * its own database-api-spec.md-parity unit test is T2.15 (`GET /api/users/me/progress`) — T2.15 is expected
 * to import this exact module rather than redefine the table, same as `ios/Laju/PointFormula`'s Swift copy
 * on the client side (T1.3).
 *
 * v1 starting values — not final, needs tuning with real data (database-api-spec.md §1's own note, same
 * status as the pace-multiplier table).
 */

export interface LevelThreshold {
  level: number;
  pointsRequired: number;
  title: string;
}

export const LEVEL_THRESHOLDS: LevelThreshold[] = [
  { level: 1, pointsRequired: 0, title: "Pemula" },
  { level: 2, pointsRequired: 100, title: "Rajin" },
  { level: 3, pointsRequired: 300, title: "Konsisten" },
  { level: 4, pointsRequired: 700, title: "Gigih" },
  { level: 5, pointsRequired: 1500, title: "Veteran" },
  { level: 6, pointsRequired: 3000, title: "Elit" },
  { level: 7, pointsRequired: 6000, title: "Master" },
  { level: 8, pointsRequired: 12000, title: "Legenda" },
];

/**
 * Highest level whose `pointsRequired` <= `totalPoints` (database-api-spec.md §1). No cap beyond level 8
 * in v1 — a user past level 8's threshold simply stays at 8 until the table is extended.
 */
export function currentLevelForPoints(totalPoints: number): number {
  let level = LEVEL_THRESHOLDS[0]!.level;
  for (const threshold of LEVEL_THRESHOLDS) {
    if (threshold.pointsRequired <= totalPoints) {
      level = threshold.level;
    } else {
      break;
    }
  }
  return level;
}
