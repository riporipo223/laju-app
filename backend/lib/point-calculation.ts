/**
 * T2.6: server-side point calculation — the authoritative counterpart to
 * `ios/Laju/PointFormula/PointFormula.swift` (T1.1). Not a literal shared import (impossible cross-language
 * post-pivot, ADR-0007) — parity is enforced by both sides passing the same fixture rows in
 * `shared/point-formula.fixtures.json` (tech-spec.md §2.2b), not by this file being "the same code."
 *
 * Deliberately decoupled from `gps_route` — takes `distanceKm`/`avgPaceSecPerKm` directly, the same
 * top-level values the client's optimistic estimate used. `gps_route`'s per-point detail belongs to
 * anti-cheat (T2.7–T2.10), not this module.
 *
 * Assumes clean input — no anti-cheat filtering here (T2.12a applies that to the aggregate result before
 * this function's output becomes `final_points_awarded`).
 */

// tech-spec.md §2.2 — starting values, not final; needs real-run-data tuning (same status as the pace
// bracket table below).
export const STREAK_BONUS_PER_DAY = 2;
export const STREAK_CAP_DAYS = 7;

// tech-spec.md §2.2 — anti-farming gate (ADR-0009): below this, total points (base AND streak bonus
// together) are zero. 100m is deliberately 5x the client's stationary-anchor radius (20m) so GPS noise
// alone cannot cross it.
export const MIN_DISTANCE_KM_FOR_POINTS = 0.1;

/** tech-spec.md §2.3 — half-open brackets `[lower, upper)`, so no pace value matches two brackets at once. */
export function paceMultiplier(avgPaceSecPerKm: number): number {
  if (avgPaceSecPerKm < 180) return 0.5; // < 3:00/km
  if (avgPaceSecPerKm < 240) return 1.2; // [3:00, 4:00)
  if (avgPaceSecPerKm < 420) return 1.0; // [4:00, 7:00)
  if (avgPaceSecPerKm < 600) return 0.9; // [7:00, 10:00)
  return 0.7; // >= 10:00/km
}

export function calculatePoints(
  distanceKm: number,
  avgPaceSecPerKm: number,
  streakDays: number
): number {
  if (distanceKm < MIN_DISTANCE_KM_FOR_POINTS) return 0;
  const multiplier = paceMultiplier(avgPaceSecPerKm);
  const basePoints = distanceKm * multiplier;
  const cappedStreakDays = Math.min(streakDays, STREAK_CAP_DAYS);
  const streakBonus = cappedStreakDays * STREAK_BONUS_PER_DAY;
  return basePoints + streakBonus;
}
