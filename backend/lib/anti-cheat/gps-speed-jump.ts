import { type GPSPoint, speedKmh } from "../gps-geometry";
import type { AntiCheatResult } from "./pace-cap";

// tech-spec.md §2.4. Exported so T4.22's severe-speed-violation check (severe-speed-violation.ts)
// reuses this exact binding — product-spec.md §4.29's explicit instruction, not a second literal
// that could silently drift from this one.
export const SPEED_CAP_KMH = 25;
const SUSTAINED_SAMPLES = 3; // ">3 consecutive samples" — at least 4 consecutive over-cap segments

/**
 * T2.8 — tech-spec.md §2.4's GPS speed jump row: instantaneous speed between two consecutive points
 * >25 km/h, sustained across >3 consecutive segments, excludes those segments.
 *
 * Flag naming follows database-api-spec.md §2.2's own literal example
 * (`"gps_speed_jump_segment_3"`) — per-segment-indexed, unlike pace-cap's flat `"pace_cap_exceeded"`
 * (that difference is the spec's own precedent, not invented here).
 *
 * Does NOT decide run `status` — only excludes segments and records flags. Status determination
 * (`validated`/`flagged`/`rejected` via `FLAG_THRESHOLD_PCT`/`REJECT_THRESHOLD_PCT`) is T2.12a's job
 * alone (tech-spec.md §2.4.1), so this module has no threshold-crossing logic beyond the 25km/h cap
 * itself.
 */
export function checkGpsSpeedJump(route: GPSPoint[]): AntiCheatResult {
  const excluded = new Set<number>();
  const flags: string[] = [];

  let runStart = -1; // segment index where the current over-cap streak began, -1 = no active streak

  const flushRun = (runEndExclusive: number) => {
    if (runStart === -1) return;
    const streakLength = runEndExclusive - runStart;
    if (streakLength > SUSTAINED_SAMPLES) {
      for (let s = runStart; s < runEndExclusive; s++) {
        excluded.add(s);
        flags.push(`gps_speed_jump_segment_${s}`);
      }
    }
    runStart = -1;
  };

  for (let i = 0; i < route.length - 1; i++) {
    const speed = speedKmh(route[i]!, route[i + 1]!);
    if (speed > SPEED_CAP_KMH) {
      if (runStart === -1) runStart = i;
    } else {
      flushRun(i);
    }
  }
  flushRun(route.length - 1);

  return { excludedSegmentIndices: [...excluded].sort((a, b) => a - b), anomalyFlags: flags };
}
