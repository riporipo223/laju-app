/**
 * Shared GPS distance/time helpers for the anti-cheat checks (T2.7–T2.10). One implementation of
 * point-to-point distance so every check measures segments the same way — kept separate from
 * `point-calculation.ts` (T2.6), which never reads `gps_route` at all (tech-spec.md §2.4's checks operate
 * on the route; the point formula operates on the client-asserted top-level distance/duration).
 */

export interface GPSPoint {
  lat: number;
  lng: number;
  timestamp: string;
  elevation: number;
}

const EARTH_RADIUS_M = 6371000;

/** Great-circle distance between two points, in meters. */
export function haversineMeters(a: GPSPoint, b: GPSPoint): number {
  const p1 = (a.lat * Math.PI) / 180;
  const p2 = (b.lat * Math.PI) / 180;
  const dPhi = ((b.lat - a.lat) * Math.PI) / 180;
  const dLambda = ((b.lng - a.lng) * Math.PI) / 180;
  const h =
    Math.sin(dPhi / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dLambda / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

/** Seconds between two points' timestamps. */
export function secondsBetween(a: GPSPoint, b: GPSPoint): number {
  return (new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()) / 1000;
}

/** Instantaneous speed between two consecutive points, in km/h. */
export function speedKmh(a: GPSPoint, b: GPSPoint): number {
  const dt = secondsBetween(a, b);
  if (dt <= 0) return 0;
  return (haversineMeters(a, b) / dt) * 3.6;
}
