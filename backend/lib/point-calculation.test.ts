import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { calculatePoints } from "./point-calculation";

interface FixtureRow {
  input: { distance_km: number; avg_pace_sec_per_km: number; streak_days: number };
  expected_points: number;
  note: string;
}

// tech-spec.md §2.2b: fixture-parity, not a literal shared import (ADR-0007). Read from the repo-root
// `shared/` file both sides consume — repo-coding-rules.md §4's PR checklist requires touching this file
// whenever the formula changes, on both sides at once.
const fixturesPath = join(__dirname, "..", "..", "shared", "point-formula.fixtures.json");
const fixtures: FixtureRow[] = JSON.parse(readFileSync(fixturesPath, "utf-8"));

describe("calculatePoints — fixture parity (shared/point-formula.fixtures.json)", () => {
  // Same empty-fixture guard as T1.1's own test (tech-spec.md §2.2b) — neither side can pass this DoD
  // against a vacuous fixture.
  it("the fixture file is non-empty", () => {
    expect(fixtures.length).toBeGreaterThan(0);
  });

  it.each(fixtures)("$note", ({ input, expected_points }) => {
    const result = calculatePoints(input.distance_km, input.avg_pace_sec_per_km, input.streak_days);
    expect(result).toBeCloseTo(expected_points, 6);
  });
});
