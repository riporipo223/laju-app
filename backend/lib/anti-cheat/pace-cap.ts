import { type GPSPoint, haversineMeters, secondsBetween } from "../gps-geometry";

const PACE_CAP_SEC_PER_KM = 180; // 3:00/km, tech-spec.md §2.4
const SUSTAINED_DISTANCE_M = 1000; // >1km, same row
const ANOMALY_FLAG = "pace_cap_exceeded";

export interface AntiCheatResult {
  /** Indices into `gps_route` identifying excluded point-pair segments — segment `i` is the pair
   *  `(route[i], route[i+1])` (tech-spec.md §2.4's "segment" definition). */
  excludedSegmentIndices: number[];
  anomalyFlags: string[];
}

/**
 * T2.7 — tech-spec.md §2.4's Pace cap row: "Avg pace < 3:00/km untuk segmen >1km berturut-turut" excludes
 * that segment. "Segmen >1km" is a *sustained window*, not a single point-pair — this scans every
 * candidate window [i, j) whose cumulative distance first reaches 1km, and excludes all point-pair
 * segments inside a window whose average pace breaches the cap.
 *
 * O(n²) worst case (route length × window scan) — acceptable for v1 given Fase 1's own run-count scale
 * note (`PersistenceController.swift`'s "dozen-ish for internal dogfood" comment applies the same
 * reasoning here); revisit if p95 latency (tech-spec.md §4 NFR) is ever threatened by route length.
 */
export function checkPaceCap(route: GPSPoint[]): AntiCheatResult {
  const excluded = new Set<number>();

  for (let i = 0; i < route.length - 1; i++) {
    let cumulativeDistance = 0;
    let j = i;
    while (j < route.length - 1 && cumulativeDistance < SUSTAINED_DISTANCE_M) {
      const from = route[j];
      const to = route[j + 1];
      if (!from || !to) break;
      cumulativeDistance += haversineMeters(from, to);
      j++;
    }
    if (cumulativeDistance < SUSTAINED_DISTANCE_M) break; // route too short from here on to ever reach 1km

    const startPoint = route[i];
    const endPoint = route[j];
    if (!startPoint || !endPoint) continue;
    const elapsedSeconds = secondsBetween(startPoint, endPoint);
    if (elapsedSeconds <= 0) continue;
    const avgPaceSecPerKm = elapsedSeconds / (cumulativeDistance / 1000);

    if (avgPaceSecPerKm < PACE_CAP_SEC_PER_KM) {
      for (let k = i; k < j; k++) excluded.add(k);
    }
  }

  return {
    excludedSegmentIndices: [...excluded].sort((a, b) => a - b),
    anomalyFlags: excluded.size > 0 ? [ANOMALY_FLAG] : [],
  };
}
