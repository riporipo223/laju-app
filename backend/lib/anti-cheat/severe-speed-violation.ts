import { type GPSPoint, secondsBetween, speedKmh } from "../gps-geometry";
import { SPEED_CAP_KMH } from "./gps-speed-jump";

// product-spec.md §4.29 AC1 — "5 detections... consecutively, within a rolling 2-minute window."
const CONSECUTIVE_THRESHOLD = 5;
const WINDOW_SECONDS = 120;

/** Distinguishes this outcome from an ordinary HIGH flag in `anomaly_flags` — `trust-score.ts` looks
 * for this exact string to apply the heavier penalty (§4.29 AC4), and `status-resolution.ts` adds it
 * whenever this check triggers. */
export const SEVERE_SPEED_VIOLATION_FLAG = "severe_speed_violation";

/**
 * T4.22 (product-spec.md §4.29): a SECOND, independent rule layered on top of T2.8's speed-jump
 * check — reuses the exact same `SPEED_CAP_KMH` (25 km/h) threshold, but a different compounding
 * condition. T2.8 excludes a segment only after >3 consecutive over-cap segments (a sustained-jump
 * exclusion rule feeding `excluded_pct`); this checks a stricter, independent pattern — 5
 * consecutive over-cap segments whose own timestamps span no more than 2 minutes — and its result
 * is NOT segment exclusion, just a single triggered/not-triggered outcome for the whole run
 * (§4.29 AC4: forces the run to 0 points + a heavier trust-score penalty, overriding whatever
 * `excluded_pct` alone would have produced).
 *
 * No separate "was the user paused/stopped mid-streak" check exists — a real pause leaves a large
 * gap between consecutive `gps_route` points (T1.2b: pause never fabricates intermediate points),
 * which would almost certainly push the streak's own span past the 2-minute window on its own.
 * Requiring the window bound already does this job; a second explicit gap threshold would just be
 * an unjustified extra number invented for a case the window already excludes.
 */
export function checkSevereSpeedViolation(route: GPSPoint[]): { triggered: boolean } {
  let streakEndPoints: GPSPoint[] = [];

  for (let i = 0; i < route.length - 1; i++) {
    const speed = speedKmh(route[i]!, route[i + 1]!);
    if (speed > SPEED_CAP_KMH) {
      streakEndPoints.push(route[i + 1]!);
      if (streakEndPoints.length >= CONSECUTIVE_THRESHOLD) {
        const windowStart = streakEndPoints[streakEndPoints.length - CONSECUTIVE_THRESHOLD]!;
        const windowEnd = streakEndPoints[streakEndPoints.length - 1]!;
        if (secondsBetween(windowStart, windowEnd) <= WINDOW_SECONDS) {
          return { triggered: true };
        }
      }
    } else {
      streakEndPoints = []; // AC2 — a clean sample resets the count to 0
    }
  }

  return { triggered: false };
}
