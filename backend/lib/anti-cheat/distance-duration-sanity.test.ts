import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { GPSPoint } from "../gps-geometry";
import { checkDistanceDurationSanity } from "./distance-duration-sanity";

function loadFixture(name: string): GPSPoint[] {
  const path = join(__dirname, "..", "..", "fixtures", "gps-routes", `${name}.json`);
  return JSON.parse(readFileSync(path, "utf-8")).gps_route;
}

describe("checkDistanceDurationSanity — against T2.6b's real fixture corpus", () => {
  it("excludes the segment and flags an implausible single-jump route (teleport fixture)", () => {
    const result = checkDistanceDurationSanity(loadFixture("teleport"));
    expect(result.excludedSegmentIndices.length).toBeGreaterThan(0);
    expect(result.anomalyFlags.every((f) => f.startsWith("distance_duration_sanity_segment_"))).toBe(
      true
    );
  });

  it("does not false-positive on either clean-control fixture", () => {
    expect(checkDistanceDurationSanity(loadFixture("clean-negative-control-easy-jog")).anomalyFlags).toEqual(
      []
    );
    expect(checkDistanceDurationSanity(loadFixture("clean-negative-control-fast-run")).anomalyFlags).toEqual(
      []
    );
  });

  it("does not cross-trigger on the sustained-but-not-instantaneous gps-speed-jump fixture (~40km/h, well under this check's 150km/h)", () => {
    expect(checkDistanceDurationSanity(loadFixture("gps-speed-jump")).anomalyFlags).toEqual([]);
  });

  it("does not trigger across a real pause gap — a genuine time gap with no location jump", () => {
    // Scope's own explicit note: GPS logging stops entirely during a pause (T1.2b), producing a real
    // time gap but no intermediate points and no location jump — by construction there is nothing
    // for this check to flag. Verified directly, not just trusted from the comment.
    const pausedRoute: GPSPoint[] = [
      { lat: -6.2, lng: 106.8, timestamp: "2026-09-08T06:00:00Z", elevation: 40 },
      { lat: -6.2001, lng: 106.8, timestamp: "2026-09-08T06:00:05Z", elevation: 40 },
      // 10-minute pause gap here — same position resumed, no jump
      { lat: -6.20011, lng: 106.8, timestamp: "2026-09-08T06:10:05Z", elevation: 40 },
      { lat: -6.20021, lng: 106.8, timestamp: "2026-09-08T06:10:10Z", elevation: 40 },
    ];
    expect(checkDistanceDurationSanity(pausedRoute).anomalyFlags).toEqual([]);
  });
});
