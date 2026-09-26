import { describe, expect, it } from "vitest";
import { computeClubAnalytics } from "./club-analytics";

describe("computeClubAnalytics", () => {
  it("sums total distance and total points across every qualifying run", () => {
    const result = computeClubAnalytics({
      runs: [
        { userId: "u1", distanceMeters: 5000, finalPointsAwarded: 10 },
        { userId: "u2", distanceMeters: 3000, finalPointsAwarded: 6 },
      ],
      topN: 5,
    });
    expect(result.totalDistanceMeters).toBe(8000);
    expect(result.totalPoints).toBe(16);
  });

  it("treats a null final_points_awarded as zero, not a crash", () => {
    const result = computeClubAnalytics({
      runs: [{ userId: "u1", distanceMeters: 5000, finalPointsAwarded: null }],
      topN: 5,
    });
    expect(result.totalPoints).toBe(0);
  });

  it("counts active members as the distinct set of contributing users", () => {
    const result = computeClubAnalytics({
      runs: [
        { userId: "u1", distanceMeters: 5000, finalPointsAwarded: 10 },
        { userId: "u1", distanceMeters: 2000, finalPointsAwarded: 4 },
        { userId: "u2", distanceMeters: 3000, finalPointsAwarded: 6 },
      ],
      topN: 5,
    });
    expect(result.activeMemberCount).toBe(2);
  });

  it("ranks top contributors by distance, descending, capped at topN", () => {
    const result = computeClubAnalytics({
      runs: [
        { userId: "u1", distanceMeters: 3000, finalPointsAwarded: 6 },
        { userId: "u2", distanceMeters: 9000, finalPointsAwarded: 18 },
        { userId: "u3", distanceMeters: 6000, finalPointsAwarded: 12 },
      ],
      topN: 2,
    });
    expect(result.topContributors).toEqual([
      { userId: "u2", distanceMeters: 9000, points: 18 },
      { userId: "u3", distanceMeters: 6000, points: 12 },
    ]);
  });

  it("returns all zeros for an empty run list", () => {
    const result = computeClubAnalytics({ runs: [], topN: 5 });
    expect(result).toEqual({ totalDistanceMeters: 0, totalPoints: 0, activeMemberCount: 0, topContributors: [] });
  });
});
