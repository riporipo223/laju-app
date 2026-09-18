import { type GPSPoint, speedKmh } from "../gps-geometry";
import type { AntiCheatResult } from "./pace-cap";

/**
 * tech-spec.md §2.4's Distance/duration sanity row describes this qualitatively ("GPS loncat lokasi jauh
 * dalam interval pendek") without a specific number, unlike pace cap (3:00/km) and GPS speed jump
 * (25 km/h) which are both explicit. **Starting value, not final** — same status as
 * `MIN_DISTANCE_KM_FOR_POINTS`/`STREAK_BONUS_PER_DAY` (tech-spec.md §2.2) and the pace-multiplier table
 * (§2.3): a defensible default pending real-run-data calibration, not a number handed down by the spec.
 *
 * 150 km/h, single segment, no sustained-count requirement: comfortably above any plausible land-vehicle
 * speed a runner might accidentally record through (distinguishing it from T2.8's 25 km/h "could this be
 * a bike/car" cap), and deliberately requires only ONE segment — a genuine teleport (a GPS fix glitch or
 * spoofed coordinate) is instantaneous by nature, not sustained, which is exactly what separates this
 * check from T2.8's sustained->3-samples one. See `gps-speed-jump.test.ts`'s explicit boundary test: the
 * `teleport.json` fixture's single ~3596 km/h spike does NOT trigger T2.8, and must trigger this check
 * instead.
 */
export const IMPLAUSIBLE_JUMP_SPEED_KMH = 150;

/**
 * T2.9 — teleport detection. Excludes any single segment whose instantaneous speed exceeds
 * `IMPLAUSIBLE_JUMP_SPEED_KMH`. Does not decide run `status` (T2.12a's job alone, tech-spec.md §2.4.1) —
 * same rule as T2.8.
 *
 * Auto-pause/manual-pause gaps (T1.2b) do not trigger this by construction: GPS logging stops entirely
 * during a pause rather than being filtered, so there is no location jump to detect across the gap — no
 * special-case handling needed, per this task's own Scope note.
 */
export function checkDistanceDurationSanity(route: GPSPoint[]): AntiCheatResult {
  const excluded = new Set<number>();
  const flags: string[] = [];

  for (let i = 0; i < route.length - 1; i++) {
    const speed = speedKmh(route[i]!, route[i + 1]!);
    if (speed > IMPLAUSIBLE_JUMP_SPEED_KMH) {
      excluded.add(i);
      flags.push(`distance_duration_sanity_segment_${i}`);
    }
  }

  return { excludedSegmentIndices: [...excluded].sort((a, b) => a - b), anomalyFlags: flags };
}
