/**
 * T2.12a — the single place that owns the aggregate `validated`/`flagged`/`rejected` decision
 * (tech-spec.md §2.4.1). T2.7-T2.10 each decide their own exclusions/flags but explicitly do NOT decide
 * status themselves (fix to Round 2 finding B-5, noted in gps-speed-jump.ts's own comment) — this module
 * is where all four checks' outputs get combined into one number and compared against threshold config.
 */

import { checkDistanceDurationSanity } from "./distance-duration-sanity";
import { checkElevationAnomaly } from "./elevation-anomaly";
import { checkGpsSpeedJump } from "./gps-speed-jump";
import type { GPSPoint } from "../gps-geometry";
import { checkPaceCap } from "./pace-cap";

// tech-spec.md §2.4.1 — configuration, not hardcoded inline in resolveRunStatus below.
export const FLAG_THRESHOLD_PCT = 10;
export const REJECT_THRESHOLD_PCT = 50;
export const FLAG_LOW_MAX_PCT = 25;

export type RunStatus = "validated" | "flagged" | "rejected";
export type FlagConfidence = "low" | "high" | null;

export interface RunResolution {
  status: RunStatus;
  flagConfidence: FlagConfidence;
  excludedSegmentIndices: number[];
  anomalyFlags: string[];
  excludedPct: number;
}

/**
 * The pure threshold decision, split out from `resolveRunStatus` so boundary behavior (the actual DoD
 * requirement) can be unit-tested at exact percentages directly — real GPS fixtures can't be engineered to
 * land on precise values like `24.999%` vs `25%`, only the physics-based checks that produce them can.
 */
export function resolveStatusFromExcludedPct(
  excludedPct: number
): { status: RunStatus; flagConfidence: FlagConfidence } {
  if (excludedPct >= REJECT_THRESHOLD_PCT) {
    return { status: "rejected", flagConfidence: null };
  }
  if (excludedPct >= FLAG_THRESHOLD_PCT) {
    return { status: "flagged", flagConfidence: excludedPct < FLAG_LOW_MAX_PCT ? "low" : "high" };
  }
  return { status: "validated", flagConfidence: null };
}

/**
 * `excluded_pct` is count-based (segments excluded by at least one check / total segments), never
 * distance-weighted (tech-spec.md §2.4's explicit "Metrik status — count-based, BUKAN berbasis jarak").
 * A segment flagged by more than one check is still counted once — the union, not the sum.
 *
 * `checkElevationAnomaly` runs last and receives the union from the other three: it never excludes a
 * segment on its own (T2.10's whole point), only adds a flag when a segment it agrees with is already
 * excluded by something else.
 */
export function resolveRunStatus(route: GPSPoint[]): RunResolution {
  const totalSegments = Math.max(0, route.length - 1);

  const paceCap = checkPaceCap(route);
  const speedJump = checkGpsSpeedJump(route);
  const sanity = checkDistanceDurationSanity(route);

  const excluded = new Set<number>([
    ...paceCap.excludedSegmentIndices,
    ...speedJump.excludedSegmentIndices,
    ...sanity.excludedSegmentIndices,
  ]);

  const elevation = checkElevationAnomaly(route, excluded);

  const anomalyFlags = [
    ...paceCap.anomalyFlags,
    ...speedJump.anomalyFlags,
    ...sanity.anomalyFlags,
    ...elevation.anomalyFlags,
  ];

  // No segments at all (route.length <= 1) — nothing to exclude, cannot divide by zero, always validated.
  const excludedPct = totalSegments === 0 ? 0 : (excluded.size / totalSegments) * 100;
  const { status, flagConfidence } = resolveStatusFromExcludedPct(excludedPct);

  return {
    status,
    flagConfidence,
    excludedSegmentIndices: [...excluded].sort((a, b) => a - b),
    anomalyFlags,
    excludedPct,
  };
}
