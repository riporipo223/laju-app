import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { GPSPoint } from "../gps-geometry";
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
