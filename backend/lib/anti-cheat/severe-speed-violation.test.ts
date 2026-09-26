import { describe, expect, it } from "vitest";
import type { GPSPoint } from "../gps-geometry";
import { checkSevereSpeedViolation } from "./severe-speed-violation";

const METERS_PER_DEGREE_LAT = 111_320;

/** Builds a synthetic route: `speedsKmh[i]` is the segment speed from point i to i+1, each segment
 * `intervalSeconds` apart, moving north only (longitude fixed) so distance is purely a function of
 * `deltaLat` — same synthetic-fixture approach the CQ-11 iOS fix used for its own GPS-derived tests. */
function buildRoute(speedsKmh: number[], intervalSeconds: number, startTimestamp = new Date("2026-09-27T06:00:00Z")): GPSPoint[] {
  const points: GPSPoint[] = [{ lat: 0, lng: 0, timestamp: startTimestamp.toISOString(), elevation: 0 }];
  let lat = 0;
  let time = startTimestamp.getTime();
  for (const speedKmh of speedsKmh) {
    const distanceMeters = (speedKmh / 3.6) * intervalSeconds;
    lat += distanceMeters / METERS_PER_DEGREE_LAT;
    time += intervalSeconds * 1000;
    points.push({ lat, lng: 0, timestamp: new Date(time).toISOString(), elevation: 0 });
  }
  return points;
}

describe("checkSevereSpeedViolation — product-spec.md §4.29 AC1/AC2", () => {
  it("does not trigger on fewer than 5 consecutive violations", () => {
    // 4 consecutive over-cap segments (30 km/h > 25 km/h cap), 10s apart — well within 2 minutes.
    const route = buildRoute([30, 30, 30, 30], 10);
    expect(checkSevereSpeedViolation(route).triggered).toBe(false);
  });

  it("triggers on exactly 5 consecutive violations within the 2-minute window", () => {
    const route = buildRoute([30, 30, 30, 30, 30], 10); // 5 segments, 40s total span
    expect(checkSevereSpeedViolation(route).triggered).toBe(true);
  });

  it("does not trigger when 5 violations occur but are NOT consecutive (a clean sample in between resets the streak)", () => {
    // 3 violations, one clean (12 km/h, under cap), then 3 more — never 5 in a row.
    const route = buildRoute([30, 30, 30, 12, 30, 30, 30], 10);
    expect(checkSevereSpeedViolation(route).triggered).toBe(false);
  });

  it("resets the count the moment a clean sample is read, per AC2 — confirmed by a streak of 5 starting fresh AFTER a clean sample", () => {
    // 4 violations, one clean, then 5 more consecutive (the fresh streak this reset enables).
    const route = buildRoute([30, 30, 30, 30, 12, 30, 30, 30, 30, 30], 10);
    expect(checkSevereSpeedViolation(route).triggered).toBe(true);
  });

  it("does not trigger when 5 consecutive violations are spread across more than 2 minutes (sparse GPS)", () => {
    // 5 consecutive violations, but 40s apart each — total span 160s, over the 120s window.
    const route = buildRoute([30, 30, 30, 30, 30], 40);
    expect(checkSevereSpeedViolation(route).triggered).toBe(false);
  });

  it("does not false-positive on a clean, steady easy-jog route", () => {
    const route = buildRoute(Array(20).fill(10), 5); // 10 km/h steady, well under the 25 km/h cap
    expect(checkSevereSpeedViolation(route).triggered).toBe(false);
  });
});
