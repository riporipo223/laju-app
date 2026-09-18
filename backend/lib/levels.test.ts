import { describe, expect, it } from "vitest";
import { currentLevelForPoints, LEVEL_THRESHOLDS, pointsToNextLevel } from "./levels";

describe("LEVEL_THRESHOLDS — matches database-api-spec.md §1's table exactly, row for row", () => {
  it("has the exact 8 rows from the spec", () => {
    expect(LEVEL_THRESHOLDS).toEqual([
      { level: 1, pointsRequired: 0, title: "Pemula" },
      { level: 2, pointsRequired: 100, title: "Rajin" },
      { level: 3, pointsRequired: 300, title: "Konsisten" },
      { level: 4, pointsRequired: 700, title: "Gigih" },
      { level: 5, pointsRequired: 1500, title: "Veteran" },
      { level: 6, pointsRequired: 3000, title: "Elit" },
      { level: 7, pointsRequired: 6000, title: "Master" },
      { level: 8, pointsRequired: 12000, title: "Legenda" },
    ]);
  });
});

describe("currentLevelForPoints", () => {
  it("returns level 1 at zero points", () => {
    expect(currentLevelForPoints(0)).toBe(1);
  });

  it("returns level 1 just below the level 2 threshold", () => {
    expect(currentLevelForPoints(99)).toBe(1);
  });

  it("returns level 2 exactly at its threshold — inclusive lower bound", () => {
    expect(currentLevelForPoints(100)).toBe(2);
  });

  it("returns the correct level for a value between thresholds", () => {
    expect(currentLevelForPoints(500)).toBe(3);
  });

  it("returns level 8 exactly at its threshold", () => {
    expect(currentLevelForPoints(12000)).toBe(8);
  });

  it("stays at level 8 for any points beyond the top threshold — no cap error", () => {
    expect(currentLevelForPoints(999999)).toBe(8);
  });
});

describe("pointsToNextLevel", () => {
  it("counts down to level 2 from zero points", () => {
    expect(pointsToNextLevel(0)).toBe(100);
  });

  it("counts down correctly mid-way to the next level", () => {
    expect(pointsToNextLevel(500)).toBe(200); // level 3 (300), next is level 4 (700)
  });

  it("is 0 right at the top level's own threshold", () => {
    expect(pointsToNextLevel(12000)).toBe(0);
  });

  it("is 0 for any points beyond the top level — no negative countdown", () => {
    expect(pointsToNextLevel(999999)).toBe(0);
  });
});
