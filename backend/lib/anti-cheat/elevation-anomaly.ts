import { type GPSPoint, secondsBetween } from "../gps-geometry";
import type { AntiCheatResult } from "./pace-cap";

/**
 * tech-spec.md §2.4's Elevation anomaly row, same as T2.9's threshold: qualitative in the spec
 * ("perubahan elevasi tidak wajar dalam waktu singkat"), no explicit number. Starting value, not final —
 * same "pending real-run-data calibration" status as `IMPLAUSIBLE_JUMP_SPEED_KMH` (T2.9) and the
 * pace-bracket table. 50m within 5s: comfortably below `fixtures/gps-routes/elevation-anomaly.json`'s
 * 100m/2s construction, so that fixture reliably trips it.
 */
export const ELEVATION_ANOMALY_THRESHOLD_M = 50;
export const ELEVATION_ANOMALY_WINDOW_SECONDS = 5;

/**
 * T2.10 — **supporting signal only, never a standalone trigger** (tech-spec.md §2.4: "Tambahan sinyal,
 * bukan trigger tunggal — tidak meng-exclude segmen sendirian"). Unlike T2.7-T2.9, this function's
 * `excludedSegmentIndices` is ALWAYS empty — elevation anomaly can never exclude a segment by itself,
 * only add a flag when the same segment is already excluded by another check.
 *
 * That is why the signature differs from T2.7-T2.9: it takes `otherExcludedSegmentIndices`, the union of
 * every other check's exclusions on this same run, as an explicit input rather than deciding anything in
 * isolation. T2.12a (which wires all four checks together) is expected to call this one last, after
 * computing the other three.
 */
export function checkElevationAnomaly(
  route: GPSPoint[],
  otherExcludedSegmentIndices: ReadonlySet<number>
): AntiCheatResult {
  const flags: string[] = [];

  for (let i = 0; i < route.length - 1; i++) {
    const from = route[i]!;
    const to = route[i + 1]!;
    const dt = secondsBetween(from, to);
    if (dt <= 0 || dt > ELEVATION_ANOMALY_WINDOW_SECONDS) continue;

    const elevationDelta = Math.abs(to.elevation - from.elevation);
    if (elevationDelta > ELEVATION_ANOMALY_THRESHOLD_M && otherExcludedSegmentIndices.has(i)) {
      flags.push(`elevation_anomaly_segment_${i}`);
    }
  }

  return { excludedSegmentIndices: [], anomalyFlags: flags };
}
