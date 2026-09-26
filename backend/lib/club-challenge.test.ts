import { describe, expect, it } from "vitest";
import { computeChallengeProgress, computeChallengeStatus } from "./club-challenge";

describe("computeChallengeProgress", () => {
  it("sums a distance challenge only from runs inside a member's own stint", () => {
    const result = computeChallengeProgress({
      targetType: "distance",
      history: [{ userId: "u1", joinedAt: new Date("2026-09-01T00:00:00Z"), leftAt: null }],
      currentMemberIds: new Set(["u1"]),
      runs: [
        { userId: "u1", startedAt: new Date("2026-09-05T00:00:00Z"), distanceMeters: 5000, durationSeconds: 1800 },
        { userId: "u1", startedAt: new Date("2026-09-10T00:00:00Z"), distanceMeters: 3000, durationSeconds: 1200 },
      ],
    });
    expect(result.collectiveTotal).toBe(8000);
    expect(result.ranking).toEqual([{ userId: "u1", total: 8000 }]);
  });

  it("sums a duration challenge using duration, not distance", () => {
    const result = computeChallengeProgress({
      targetType: "duration",
      history: [{ userId: "u1", joinedAt: new Date("2026-09-01T00:00:00Z"), leftAt: null }],
      currentMemberIds: new Set(["u1"]),
      runs: [{ userId: "u1", startedAt: new Date("2026-09-05T00:00:00Z"), distanceMeters: 5000, durationSeconds: 1800 }],
    });
    expect(result.collectiveTotal).toBe(1800);
    expect(result.ranking).toEqual([{ userId: "u1", total: 1800 }]);
  });

  it("does NOT count a run that happened before the member joined", () => {
    const result = computeChallengeProgress({
      targetType: "distance",
      history: [{ userId: "u1", joinedAt: new Date("2026-09-10T00:00:00Z"), leftAt: null }],
      currentMemberIds: new Set(["u1"]),
      runs: [{ userId: "u1", startedAt: new Date("2026-09-05T00:00:00Z"), distanceMeters: 5000, durationSeconds: 1800 }],
    });
    expect(result.collectiveTotal).toBe(0);
    expect(result.ranking).toEqual([]);
  });

  it("a departed member's past contribution still counts in the collective total (never decreases)", () => {
    const result = computeChallengeProgress({
      targetType: "distance",
      history: [{ userId: "u1", joinedAt: new Date("2026-09-01T00:00:00Z"), leftAt: new Date("2026-09-08T00:00:00Z") }],
      currentMemberIds: new Set(), // u1 is no longer a current member
      runs: [{ userId: "u1", startedAt: new Date("2026-09-05T00:00:00Z"), distanceMeters: 5000, durationSeconds: 1800 }],
    });
    expect(result.collectiveTotal).toBe(5000);
  });

  it("but a departed member is removed from the individual ranking display", () => {
    const result = computeChallengeProgress({
      targetType: "distance",
      history: [{ userId: "u1", joinedAt: new Date("2026-09-01T00:00:00Z"), leftAt: new Date("2026-09-08T00:00:00Z") }],
      currentMemberIds: new Set(),
      runs: [{ userId: "u1", startedAt: new Date("2026-09-05T00:00:00Z"), distanceMeters: 5000, durationSeconds: 1800 }],
    });
    expect(result.ranking).toEqual([]);
  });

  it("does NOT count a run submitted after the member already left", () => {
    const result = computeChallengeProgress({
      targetType: "distance",
      history: [{ userId: "u1", joinedAt: new Date("2026-09-01T00:00:00Z"), leftAt: new Date("2026-09-08T00:00:00Z") }],
      currentMemberIds: new Set(["u1"]), // e.g. rejoined later — still shouldn't retroactively count this old run
      runs: [{ userId: "u1", startedAt: new Date("2026-09-15T00:00:00Z"), distanceMeters: 5000, durationSeconds: 1800 }],
    });
    expect(result.collectiveTotal).toBe(0);
  });

  it("ranks current members by descending contribution", () => {
    const history = [
      { userId: "u1", joinedAt: new Date("2026-09-01T00:00:00Z"), leftAt: null },
      { userId: "u2", joinedAt: new Date("2026-09-01T00:00:00Z"), leftAt: null },
    ];
    const result = computeChallengeProgress({
      targetType: "distance",
      history,
      currentMemberIds: new Set(["u1", "u2"]),
      runs: [
        { userId: "u1", startedAt: new Date("2026-09-05T00:00:00Z"), distanceMeters: 3000, durationSeconds: 900 },
        { userId: "u2", startedAt: new Date("2026-09-05T00:00:00Z"), distanceMeters: 7000, durationSeconds: 2100 },
      ],
    });
    expect(result.ranking).toEqual([
      { userId: "u2", total: 7000 },
      { userId: "u1", total: 3000 },
    ]);
  });
});

describe("computeChallengeStatus", () => {
  it("stays active before the deadline when the target isn't met", () => {
    const status = computeChallengeStatus({
      storedStatus: "active",
      deadline: new Date("2026-10-01T00:00:00Z"),
      targetValue: 100000,
      collectiveTotal: 50000,
      now: new Date("2026-09-15T00:00:00Z"),
    });
    expect(status).toBe("active");
  });

  it("becomes target_reached before the deadline once the target is met, but does NOT close early", () => {
    const status = computeChallengeStatus({
      storedStatus: "active",
      deadline: new Date("2026-10-01T00:00:00Z"),
      targetValue: 100000,
      collectiveTotal: 120000,
      now: new Date("2026-09-15T00:00:00Z"),
    });
    expect(status).toBe("target_reached");
  });

  it("closes as closed_success after the deadline if the target was met", () => {
    const status = computeChallengeStatus({
      storedStatus: "target_reached",
      deadline: new Date("2026-09-01T00:00:00Z"),
      targetValue: 100000,
      collectiveTotal: 120000,
      now: new Date("2026-09-15T00:00:00Z"),
    });
    expect(status).toBe("closed_success");
  });

  it("closes as closed_missed after the deadline if the target was never met", () => {
    const status = computeChallengeStatus({
      storedStatus: "active",
      deadline: new Date("2026-09-01T00:00:00Z"),
      targetValue: 100000,
      collectiveTotal: 40000,
      now: new Date("2026-09-15T00:00:00Z"),
    });
    expect(status).toBe("closed_missed");
  });

  it("a cancelled challenge stays cancelled regardless of deadline/total", () => {
    const status = computeChallengeStatus({
      storedStatus: "cancelled",
      deadline: new Date("2026-09-01T00:00:00Z"),
      targetValue: 100000,
      collectiveTotal: 200000,
      now: new Date("2026-09-15T00:00:00Z"),
    });
    expect(status).toBe("cancelled");
  });
});
