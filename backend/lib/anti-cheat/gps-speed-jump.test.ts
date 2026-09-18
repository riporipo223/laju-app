import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { GPSPoint } from "../gps-geometry";
import { checkGpsSpeedJump } from "./gps-speed-jump";

function loadFixture(name: string): GPSPoint[] {
  const path = join(__dirname, "..", "..", "fixtures", "gps-routes", `${name}.json`);
  return JSON.parse(readFileSync(path, "utf-8")).gps_route;
}

describe("checkGpsSpeedJump — against T2.6b's real fixture corpus", () => {
  it("excludes segments and flags a sustained >25km/h, >3-sample jump", () => {
    const result = checkGpsSpeedJump(loadFixture("gps-speed-jump"));
    expect(result.excludedSegmentIndices.length).toBeGreaterThan(0);
    expect(result.anomalyFlags.every((f) => f.startsWith("gps_speed_jump_segment_"))).toBe(true);
  });

  it("does not false-positive on a normal easy-pace route", () => {
    expect(checkGpsSpeedJump(loadFixture("clean-negative-control-easy-jog")).anomalyFlags).toEqual([]);
  });

  it("does not false-positive on the fast-but-human clean route", () => {
    expect(checkGpsSpeedJump(loadFixture("clean-negative-control-fast-run")).anomalyFlags).toEqual([]);
  });

  it("does not cross-trigger on the pace-cap-only fixture (peaks at 24.0 km/h, under this cap)", () => {
    expect(checkGpsSpeedJump(loadFixture("pace-cap-breach")).anomalyFlags).toEqual([]);
  });

  it("does NOT trigger on a single extreme spike that isn't sustained >3 samples (teleport fixture)", () => {
    // teleport.json peaks at ~3596 km/h but only 1 sample crosses the cap — the spec requires
    // sustained >3 consecutive samples. A single spike belongs to T2.9's distance/duration-sanity
    // check, not this one. This is the exact boundary the two checks are deliberately split on.
    expect(checkGpsSpeedJump(loadFixture("teleport")).anomalyFlags).toEqual([]);
  });

  it("flags only the speed-jump tail of a combined-anomaly route, not the pace-cap head", () => {
    const result = checkGpsSpeedJump(loadFixture("combined-anomalies"));
    expect(result.anomalyFlags.length).toBeGreaterThan(0);
    // The pace-cap section is segments 0-28; the speed-jump tail starts at segment 29. This check
    // must not reach back into the pace-cap-only portion.
    expect(Math.min(...result.excludedSegmentIndices)).toBeGreaterThanOrEqual(29);
  });
});
