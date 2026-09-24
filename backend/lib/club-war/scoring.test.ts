import { describe, expect, it } from "vitest";
import {
  WAR_DURATION_MS,
  decideWarResult,
  isInWarWindow,
  isQualifyingRun,
  summarizeClub,
  type ClubTally,
} from "./scoring";
import type { RunRecord } from "./types";

const start = new Date("2026-10-01T00:00:00Z");
const run = (overrides: Partial<RunRecord> = {}): RunRecord => ({
  userId: "u1",
  startedAt: new Date(start.getTime() + 60_000),
  distanceMeters: 5000,
  status: "validated",
  finalPointsAwarded: 5,
  ...overrides,
});
const tally = (overrides: Partial<ClubTally> & { clubId: string }): ClubTally => ({
  role: "invited",
  participantCount: 10,
  activeCount: 5,
  totalDistanceMeters: 10_000,
  totalPoints: 10,
  acceptedAtMs: start.getTime(),
  ...overrides,
});

describe("isQualifyingRun (§4.20 threshold reused by §4.19 AC3)", () => {
  it("counts validated, approved and flagged runs at or above the distance gate", () => {
    expect(isQualifyingRun(run({ status: "validated" }))).toBe(true);
    expect(isQualifyingRun(run({ status: "approved" }))).toBe(true);
    expect(isQualifyingRun(run({ status: "flagged" }))).toBe(true);
    expect(isQualifyingRun(run({ distanceMeters: 100 }))).toBe(true);
  });

  it("does not count rejected runs or runs under the ADR-0009 gate", () => {
    expect(isQualifyingRun(run({ status: "rejected" }))).toBe(false);
    expect(isQualifyingRun(run({ distanceMeters: 99.9 }))).toBe(false);
  });
});

describe("isInWarWindow", () => {
  it("includes the start instant and excludes the 48h mark", () => {
    expect(isInWarWindow(run({ startedAt: start }), start)).toBe(true);
    expect(isInWarWindow(run({ startedAt: new Date(start.getTime() + WAR_DURATION_MS - 1) }), start)).toBe(true);
    expect(isInWarWindow(run({ startedAt: new Date(start.getTime() + WAR_DURATION_MS) }), start)).toBe(false);
    expect(isInWarWindow(run({ startedAt: new Date(start.getTime() - 1) }), start)).toBe(false);
  });
});

describe("summarizeClub", () => {
  it("counts each participant once, only from this club's snapshot, only qualifying runs in the window", () => {
    const participants = [
      { userId: "a", clubId: "c1" },
      { userId: "b", clubId: "c1" },
      { userId: "c", clubId: "c1" },
      { userId: "x", clubId: "c2" },
    ];
    const runs = [
      run({ userId: "a", distanceMeters: 3000, finalPointsAwarded: 3 }),
      run({ userId: "a", distanceMeters: 2000, finalPointsAwarded: 2 }),
      run({ userId: "b", status: "rejected" }),
      run({ userId: "c", startedAt: new Date(start.getTime() + WAR_DURATION_MS) }),
      run({ userId: "x" }),
      run({ userId: "outsider" }),
    ];
    const acceptedAt = new Date(start.getTime() - 60_000);
    const t = summarizeClub("c1", "inviter", participants, runs, start, acceptedAt);
    expect(t).toEqual({
      clubId: "c1",
      role: "inviter",
      participantCount: 3,
      activeCount: 1,
      totalDistanceMeters: 5000,
      totalPoints: 5,
      acceptedAtMs: acceptedAt.getTime(),
    });
  });
});

describe("decideWarResult", () => {
  it("AC4: the strictly highest participation rate wins; everyone else loses", () => {
    const result = decideWarResult(
      [
        tally({ clubId: "a", role: "inviter", activeCount: 6 }),
        tally({ clubId: "b", activeCount: 4 }),
        tally({ clubId: "c", activeCount: 5 }),
      ],
      true
    );
    expect(result.winnerClubId).toBe("a");
    expect(result.winReason).toBe("participation_rate");
    expect(result.clubs.map((c) => [c.clubId, c.outcome, c.participationRate])).toEqual([
      ["a", "win", 0.6],
      ["b", "loss", 0.4],
      ["c", "loss", 0.5],
    ]);
  });

  it("compares rates, not raw counts", () => {
    const result = decideWarResult(
      [
        tally({ clubId: "big", role: "inviter", participantCount: 100, activeCount: 30 }),
        tally({ clubId: "small", participantCount: 10, activeCount: 5 }),
      ],
      true
    );
    expect(result.winnerClubId).toBe("small");
  });

  it("AC5: a tie on rate is broken by combined distance", () => {
    const result = decideWarResult(
      [
        tally({ clubId: "a", role: "inviter", totalDistanceMeters: 20_000 }),
        tally({ clubId: "b", totalDistanceMeters: 25_000 }),
      ],
      true
    );
    expect(result).toMatchObject({ winnerClubId: "b", winReason: "tie_break" });
  });

  it("AC5: a tie on rate and distance falls through to combined points", () => {
    const result = decideWarResult(
      [tally({ clubId: "a", role: "inviter", totalPoints: 30 }), tally({ clubId: "b", totalPoints: 12 })],
      true
    );
    expect(result).toMatchObject({ winnerClubId: "a", winReason: "tie_break" });
  });

  it("AC5 final step: a tie on rate, distance and points goes to the club that accepted earliest", () => {
    const result = decideWarResult(
      [
        tally({ clubId: "a", role: "inviter", acceptedAtMs: start.getTime() - 3000 }),
        tally({ clubId: "b", acceptedAtMs: start.getTime() - 1000 }),
        tally({ clubId: "c", acceptedAtMs: start.getTime() - 2000 }),
      ],
      true
    );
    expect(result).toMatchObject({ winnerClubId: "a", winReason: "tie_break" });
  });

  it("AC5 final step only compares clubs still tied after distance and points", () => {
    const result = decideWarResult(
      [
        tally({ clubId: "a", role: "inviter", totalPoints: 9, acceptedAtMs: start.getTime() - 9000 }),
        tally({ clubId: "b", acceptedAtMs: start.getTime() - 1000 }),
        tally({ clubId: "c", acceptedAtMs: start.getTime() - 2000 }),
      ],
      true
    );
    expect(result).toMatchObject({ winnerClubId: "c", winReason: "tie_break" });
  });

  it("an identical acceptance instant falls back to club id, so a result always exists", () => {
    const result = decideWarResult([tally({ clubId: "z" }), tally({ clubId: "m", role: "inviter" })], true);
    expect(result).toMatchObject({ winnerClubId: "m", winReason: "tie_break" });
  });

  it("AC6: a club with zero active participants forfeits; the other club wins", () => {
    const result = decideWarResult(
      [tally({ clubId: "a", role: "inviter", activeCount: 0 }), tally({ clubId: "b", activeCount: 1 })],
      true
    );
    expect(result).toMatchObject({ winnerClubId: "b", winReason: "forfeit_inactivity" });
    expect(result.clubs.find((c) => c.clubId === "a")?.outcome).toBe("loss");
  });

  it("AC6 in a 3-club war: the inactive club forfeits, the other two still compete on rate", () => {
    const result = decideWarResult(
      [
        tally({ clubId: "a", role: "inviter", activeCount: 2 }),
        tally({ clubId: "b", activeCount: 0 }),
        tally({ clubId: "c", activeCount: 3 }),
      ],
      true
    );
    expect(result).toMatchObject({ winnerClubId: "c", winReason: "participation_rate" });
  });

  it("AC10: the inviter forfeits when its owner's Premium lapsed, even with the best rate", () => {
    const result = decideWarResult(
      [tally({ clubId: "a", role: "inviter", activeCount: 9 }), tally({ clubId: "b", activeCount: 1 })],
      false
    );
    expect(result).toMatchObject({ winnerClubId: "b", winReason: "forfeit_premium_lapse" });
  });

  it("AC10 never applies to an invited club", () => {
    const result = decideWarResult(
      [tally({ clubId: "a", role: "inviter", activeCount: 1 }), tally({ clubId: "b", activeCount: 9 })],
      true
    );
    expect(result.winnerClubId).toBe("b");
  });

  it("AC10 in a 3-club war: the lapsed inviter loses, the remaining clubs are ranked normally", () => {
    const result = decideWarResult(
      [
        tally({ clubId: "a", role: "inviter", activeCount: 9 }),
        tally({ clubId: "b", activeCount: 3 }),
        tally({ clubId: "c", activeCount: 4 }),
      ],
      false
    );
    expect(result).toMatchObject({ winnerClubId: "c", winReason: "participation_rate" });
    expect(result.clubs.find((c) => c.clubId === "a")?.outcome).toBe("loss");
  });

  it("when every club forfeits, each forfeit applies: all lose, no winner", () => {
    const result = decideWarResult(
      [tally({ clubId: "a", role: "inviter", activeCount: 3 }), tally({ clubId: "b", activeCount: 0 })],
      false
    );
    expect(result.winnerClubId).toBeNull();
    expect(result.winReason).toBeNull();
    expect(result.clubs.every((c) => c.outcome === "loss")).toBe(true);
  });

  it("a club with no participants has rate 0 and forfeits for inactivity", () => {
    const result = decideWarResult(
      [tally({ clubId: "a", role: "inviter", participantCount: 0, activeCount: 0 }), tally({ clubId: "b" })],
      true
    );
    expect(result.clubs.find((c) => c.clubId === "a")?.participationRate).toBe(0);
    expect(result.winnerClubId).toBe("b");
  });
});
