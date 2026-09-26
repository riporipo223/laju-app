import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { GPSPoint } from "../gps-geometry";
import { SEVERE_SPEED_VIOLATION_FLAG } from "./severe-speed-violation";
import {
  FLAG_LOW_MAX_PCT,
  FLAG_THRESHOLD_PCT,
  REJECT_THRESHOLD_PCT,
  resolveRunStatus,
  resolveStatusFromExcludedPct,
} from "./status-resolution";

function loadFixture(name: string): GPSPoint[] {
  const path = join(__dirname, "..", "..", "fixtures", "gps-routes", `${name}.json`);
  return JSON.parse(readFileSync(path, "utf-8")).gps_route;
}

const METERS_PER_DEGREE_LAT = 111_320;

/** Same synthetic-route builder as severe-speed-violation.test.ts — duplicated, not imported,
 * matching this file's own established convention of a self-contained per-test-file helper
 * (`loadFixture` above is itself duplicated across every anti-cheat test file in this directory). */
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

describe("resolveStatusFromExcludedPct — tech-spec.md §2.4.1 threshold boundaries", () => {
  it("just below FLAG_THRESHOLD_PCT (10%) resolves to validated", () => {
    expect(resolveStatusFromExcludedPct(FLAG_THRESHOLD_PCT - 0.01)).toEqual({
      status: "validated",
      flagConfidence: null,
    });
  });

  it("exactly FLAG_THRESHOLD_PCT (10%) resolves to flagged/low — lower bound is inclusive", () => {
    expect(resolveStatusFromExcludedPct(FLAG_THRESHOLD_PCT)).toEqual({
      status: "flagged",
      flagConfidence: "low",
    });
  });

  it("within the LOW confidence sub-band (10%-<25%)", () => {
    expect(resolveStatusFromExcludedPct(15)).toEqual({ status: "flagged", flagConfidence: "low" });
  });

  it("exactly FLAG_LOW_MAX_PCT (25%) crosses into HIGH — lower bound is inclusive", () => {
    expect(resolveStatusFromExcludedPct(FLAG_LOW_MAX_PCT)).toEqual({
      status: "flagged",
      flagConfidence: "high",
    });
  });

  it("within the HIGH confidence sub-band (25%-<50%)", () => {
    expect(resolveStatusFromExcludedPct(40)).toEqual({ status: "flagged", flagConfidence: "high" });
  });

  it("just below REJECT_THRESHOLD_PCT (50%) is still flagged/high", () => {
    expect(resolveStatusFromExcludedPct(REJECT_THRESHOLD_PCT - 0.01)).toEqual({
      status: "flagged",
      flagConfidence: "high",
    });
  });

  it("at/above REJECT_THRESHOLD_PCT (50%) resolves to rejected", () => {
    expect(resolveStatusFromExcludedPct(REJECT_THRESHOLD_PCT)).toEqual({
      status: "rejected",
      flagConfidence: null,
    });
    expect(resolveStatusFromExcludedPct(100)).toEqual({ status: "rejected", flagConfidence: null });
  });

  it("zero exclusion resolves to validated", () => {
    expect(resolveStatusFromExcludedPct(0)).toEqual({ status: "validated", flagConfidence: null });
  });
});

describe("resolveRunStatus — wiring all four checks together against T2.6b's real fixtures", () => {
  it("a clean route resolves to validated with zero exclusions", () => {
    const result = resolveRunStatus(loadFixture("clean-negative-control-easy-jog"));
    expect(result.status).toBe("validated");
    expect(result.flagConfidence).toBeNull();
    expect(result.excludedSegmentIndices).toEqual([]);
    expect(result.excludedPct).toBe(0);
  });

  it("elevation-anomaly never excludes on its own — status decision does not come from it alone", () => {
    // elevation-anomaly.json has a real elevation jump but no other trigger, so status must stay validated.
    const result = resolveRunStatus(loadFixture("elevation-anomaly"));
    expect(result.status).toBe("validated");
    expect(result.anomalyFlags).toEqual([]);
  });

  it("a route with pace-cap breach and GPS speed jump unions both checks' exclusions, not double-counts", () => {
    const route = loadFixture("combined-anomalies");
    const result = resolveRunStatus(route);
    const totalSegments = route.length - 1;
    // The union must equal the set of indices covered by at least one check — sanity check that it's a
    // proper subset of total segments and matches a straightforward count, not an inflated sum.
    expect(result.excludedSegmentIndices.length).toBeLessThanOrEqual(totalSegments);
    expect(new Set(result.excludedSegmentIndices).size).toBe(result.excludedSegmentIndices.length);
    expect(result.excludedPct).toBeCloseTo((result.excludedSegmentIndices.length / totalSegments) * 100, 10);
  });

  it("a route with zero or one GPS point never divides by zero — resolves validated", () => {
    const singlePoint: GPSPoint[] = [{ lat: -6.2, lng: 106.8, timestamp: "2026-09-08T06:00:00Z", elevation: 10 }];
    const result = resolveRunStatus(singlePoint);
    expect(result.status).toBe("validated");
    expect(result.excludedPct).toBe(0);
  });
});

describe("resolveRunStatus — T4.22 severe speed violation override (product-spec.md §4.29 AC4)", () => {
  it("forces rejected + the severe flag when 5 consecutive speed-jump detections land within 2 minutes", () => {
    const route = buildRoute([30, 30, 30, 30, 30], 10);
    const result = resolveRunStatus(route);
    expect(result.status).toBe("rejected");
    expect(result.anomalyFlags).toContain(SEVERE_SPEED_VIOLATION_FLAG);
  });

  it("does NOT add the severe flag when violations aren't consecutive enough to trigger it", () => {
    // Only 4 consecutive over-cap segments — below the severe check's own 5-in-a-row threshold.
    // (This route's excluded_pct still resolves to `rejected` on its own via the ORDINARY
    // gps-speed-jump sustained->3 rule — a coincidence of this particular synthetic route, not
    // evidence the severe check fired. The severe flag's absence is the actual assertion here.)
    const route = buildRoute([30, 30, 30, 30], 10);
    const result = resolveRunStatus(route);
    expect(result.anomalyFlags).not.toContain(SEVERE_SPEED_VIOLATION_FLAG);
  });

  it("overrides even when excluded_pct alone would only reach flagged, not rejected — the two rules are independent", () => {
    // 5 consecutive violations (10 segments total) is 50% excluded_pct territory on its own from
    // gps-speed-jump's sustained-run rule too, so build a LONGER clean tail to dilute excluded_pct
    // well under REJECT_THRESHOLD_PCT (50%) while still tripping the severe check on the short violation burst.
    const violationBurst = [30, 30, 30, 30, 30];
    const cleanTail = Array(40).fill(10); // 40 clean segments at an easy 10 km/h
    const route = buildRoute([...violationBurst, ...cleanTail], 10);
    const result = resolveRunStatus(route);
    expect(result.excludedPct).toBeLessThan(REJECT_THRESHOLD_PCT);
    expect(result.status).toBe("rejected"); // forced by the severe check, not by excluded_pct
    expect(result.anomalyFlags).toContain(SEVERE_SPEED_VIOLATION_FLAG);
  });
});
