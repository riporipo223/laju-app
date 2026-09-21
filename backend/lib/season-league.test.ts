import { describe, expect, it } from "vitest";
import { LEAGUE_BANDS, leagueFor } from "./season-league";

describe("leagueFor", () => {
  it.each([
    [0, "bronze"],
    [79, "bronze"],
    [80, "silver"],
    [249, "silver"],
    [250, "gold"],
    [599, "gold"],
    [600, "platinum"],
    [1_000_000, "platinum"],
  ])("%i points is %s", (points, league) => {
    expect(leagueFor(points)).toBe(league);
  });

  it("a user whose points were clawed back can drop a league (compensating rows are real)", () => {
    expect(leagueFor(90)).toBe("silver");
    expect(leagueFor(90 - 40)).toBe("bronze");
  });

  it("bands are config: a custom table changes the answer without touching the logic", () => {
    const custom = [
      { league: "bronze", minPoints: 0 },
      { league: "silver", minPoints: 10 },
    ] as const;
    expect(leagueFor(10, custom)).toBe("silver");
    expect(leagueFor(9, custom)).toBe("bronze");
  });

  it("the shipped bands start at 0 and ascend, so every user always has a league", () => {
    expect(LEAGUE_BANDS[0]!.minPoints).toBe(0);
    LEAGUE_BANDS.slice(1).forEach((band, index) => expect(band.minPoints).toBeGreaterThan(LEAGUE_BANDS[index]!.minPoints));
  });
});
