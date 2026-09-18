import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { GPSPoint } from "../gps-geometry";
import { checkPaceCap } from "./pace-cap";

function loadFixture(name: string): GPSPoint[] {
  const path = join(__dirname, "..", "..", "fixtures", "gps-routes", `${name}.json`);
  return JSON.parse(readFileSync(path, "utf-8")).gps_route;
}

describe("checkPaceCap — against T2.6b's real fixture corpus, not hardcoded routes", () => {
  it("excludes segments and flags a synthetic >1km sub-3:00/km breach", () => {
    const result = checkPaceCap(loadFixture("pace-cap-breach"));
    expect(result.anomalyFlags).toEqual(["pace_cap_exceeded"]);
    expect(result.excludedSegmentIndices.length).toBeGreaterThan(0);
  });

  it("does not false-positive on a normal easy-pace route", () => {
    const result = checkPaceCap(loadFixture("clean-negative-control-easy-jog"));
    expect(result.anomalyFlags).toEqual([]);
    expect(result.excludedSegmentIndices).toEqual([]);
  });

  it("does not false-positive on a fast-but-human route deliberately close to the cap", () => {
    const result = checkPaceCap(loadFixture("clean-negative-control-fast-run"));
    expect(result.anomalyFlags).toEqual([]);
    expect(result.excludedSegmentIndices).toEqual([]);
  });

  it("flags only the pace-cap portion of a combined-anomaly route, not the GPS-speed-jump tail", () => {
    const route = loadFixture("combined-anomalies");
    const result = checkPaceCap(route);
    expect(result.anomalyFlags).toEqual(["pace_cap_exceeded"]);
    // The fixture's pace-cap section is points 0-29 (30 points); the GPS-speed-jump tail is points
    // 30-34, appended after it. A 1km-sustained-window scan starting near the pace-cap/speed-jump
    // boundary can legitimately extend one segment past it (segment 30 = pair(30,31)) to reach the
    // full 1km — that is correct sliding-window behavior, not a bug. What this check must NOT do is
    // reach deep into the speed-jump-only tail: segments 32-33 (pairs fully inside the jump, with no
    // boundary ambiguity) must stay unexcluded — that is T2.8's check's job, not this one's.
    expect(result.excludedSegmentIndices).not.toContain(32);
    expect(result.excludedSegmentIndices).not.toContain(33);
  });

  it("does not trigger on the isolated gps-speed-jump fixture (that's T2.8's check, not this one)", () => {
    const result = checkPaceCap(loadFixture("gps-speed-jump"));
    expect(result.anomalyFlags).toEqual([]);
  });
});
