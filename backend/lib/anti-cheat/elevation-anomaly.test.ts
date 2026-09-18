import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { GPSPoint } from "../gps-geometry";
import { checkElevationAnomaly } from "./elevation-anomaly";

function loadFixture(name: string): GPSPoint[] {
  const path = join(__dirname, "..", "..", "fixtures", "gps-routes", `${name}.json`);
  return JSON.parse(readFileSync(path, "utf-8")).gps_route;
}

describe("checkElevationAnomaly — against T2.6b's real fixture corpus", () => {
  const elevationRoute = loadFixture("elevation-anomaly"); // 100m jump at segment index 1

  it("NEVER excludes a segment by itself, in any scenario — this is the core scope rule", () => {
    expect(checkElevationAnomaly(elevationRoute, new Set()).excludedSegmentIndices).toEqual([]);
    expect(checkElevationAnomaly(elevationRoute, new Set([1])).excludedSegmentIndices).toEqual([]);
  });

  it("does NOT flag when there is no other trigger — 'additional signal, not a standalone trigger'", () => {
    // Empty other-checks set: no other check flagged anything on this run. The elevation jump is real
    // (100m/2s, well over the 50m/5s threshold) but must produce zero flags alone.
    const result = checkElevationAnomaly(elevationRoute, new Set());
    expect(result.anomalyFlags).toEqual([]);
  });

  it("adds the correct flag alongside another check's exclusion on the SAME segment", () => {
    // Simulates T2.12a's wiring: another check (e.g. pace cap) already excluded segment 1 on this run.
    const otherExclusions = new Set([1]);
    const result = checkElevationAnomaly(elevationRoute, otherExclusions);
    expect(result.anomalyFlags).toEqual(["elevation_anomaly_segment_1"]);
  });

  it("does not add a flag if the other check's exclusion is on a DIFFERENT segment", () => {
    // The elevation anomaly is real, but nothing else was flagged on segment 1 specifically — segment 0
    // being excluded by some other check does not correlate with this run's elevation jump.
    const otherExclusions = new Set([0]);
    const result = checkElevationAnomaly(elevationRoute, otherExclusions);
    expect(result.anomalyFlags).toEqual([]);
  });

  it("produces no flags on a clean route regardless of other-exclusions input", () => {
    const cleanRoute = loadFixture("clean-negative-control-easy-jog");
    expect(checkElevationAnomaly(cleanRoute, new Set([0, 1, 2])).anomalyFlags).toEqual([]);
  });
});
