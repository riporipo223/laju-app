import { beforeEach, describe, expect, it, vi } from "vitest";

const runSelectChain = { select: vi.fn(() => runSelectChain), eq: vi.fn(() => runSelectChain), maybeSingle: vi.fn() };
const runUpdateChain = { eq: vi.fn() };
const runUpdateMock = vi.fn((_row: unknown) => runUpdateChain);

const runQueryChain = {
  select: vi.fn(() => runQueryChain),
  eq: vi.fn(() => runQueryChain),
  lt: vi.fn(),
};

const txSelectChain = { select: vi.fn(() => txSelectChain), eq: vi.fn(() => txSelectChain), maybeSingle: vi.fn() };
const txInsertMock = vi.fn((_row: unknown) => Promise.resolve({ error: null as { message: string } | null }));

const recomputeUserPointsAggregateMock = vi.fn();
const recomputeAndPersistTrustScoreMock = vi.fn();

const fromMock = vi.fn((table: string): { select: typeof runSelectChain.select | typeof runQueryChain.select; update?: typeof runUpdateMock; insert?: typeof txInsertMock } => {
  if (table === "run") {
    // resolveFlaggedRun's own fetch-by-id/update path — autoResolveOverdueLowConfidenceFlags's overdue
    // query uses runQueryChain via a dedicated fromMock.mockImplementation override (see below).
    return { select: runSelectChain.select, update: runUpdateMock };
  }
  if (table === "point_transaction") {
    return { select: txSelectChain.select, insert: txInsertMock };
  }
  throw new Error(`unexpected table ${table}`);
});

vi.mock("../supabase", () => ({ supabaseAdmin: { from: (table: string) => fromMock(table) } }));
vi.mock("../point-transaction", () => ({
  recomputeUserPointsAggregate: (...args: unknown[]) => recomputeUserPointsAggregateMock(...args),
}));
vi.mock("../trust-score", () => ({
  recomputeAndPersistTrustScore: (...args: unknown[]) => recomputeAndPersistTrustScoreMock(...args),
}));

const {
  resolveFlaggedRun,
  autoResolveOverdueLowConfidenceFlags,
  RunNotFlaggedError,
  REVIEW_WINDOW_LOW_HOURS,
} = await import("./resolve-flagged-runs");

function flaggedRun(overrides: Partial<{ user_id: string; final_points_awarded: number }> = {}) {
  return { id: "run-1", user_id: "usr-1", status: "flagged", final_points_awarded: 5, ...overrides };
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("REVIEW_WINDOW_LOW_HOURS is configuration, not hardcoded", () => {
  it("is exported and matches tech-spec.md's 48h default", () => {
    expect(REVIEW_WINDOW_LOW_HOURS).toBe(48);
  });
});

describe("resolveFlaggedRun — approve path", () => {
  it("rejects resolving a run that is not currently 'flagged'", async () => {
    runSelectChain.maybeSingle.mockResolvedValueOnce({ data: { ...flaggedRun(), status: "validated" }, error: null });
    await expect(resolveFlaggedRun("run-1", "approved", "auto")).rejects.toThrow(RunNotFlaggedError);
  });

  it("a LOW flag auto-approved: no compensating transaction, status/resolved_via/resolved_at set, trust recomputed", async () => {
    runSelectChain.maybeSingle.mockResolvedValueOnce({ data: flaggedRun(), error: null });
    runUpdateChain.eq.mockResolvedValueOnce({ error: null });
    recomputeAndPersistTrustScoreMock.mockResolvedValueOnce(1.0);

    await resolveFlaggedRun("run-1", "approved", "auto");

    expect(txInsertMock).not.toHaveBeenCalled();
    expect(recomputeUserPointsAggregateMock).not.toHaveBeenCalled();
    const updateArg = runUpdateMock.mock.calls.at(-1)?.[0] as {
      status: string;
      resolved_via: string;
      resolved_at: string;
      final_points_awarded: number;
    };
    expect(updateArg.status).toBe("approved");
    expect(updateArg.resolved_via).toBe("auto");
    expect(updateArg.final_points_awarded).toBe(5); // unchanged on approve
    expect(typeof updateArg.resolved_at).toBe("string");
    expect(recomputeAndPersistTrustScoreMock).toHaveBeenCalledWith("usr-1");
  });

  it("a manual override to approved sets resolved_via='manual' (not 'auto')", async () => {
    runSelectChain.maybeSingle.mockResolvedValueOnce({ data: flaggedRun(), error: null });
    runUpdateChain.eq.mockResolvedValueOnce({ error: null });
    recomputeAndPersistTrustScoreMock.mockResolvedValueOnce(0.95);

    await resolveFlaggedRun("run-1", "approved", "manual");

    const updateArg = runUpdateMock.mock.calls.at(-1)?.[0] as { resolved_via: string };
    expect(updateArg.resolved_via).toBe("manual");
  });
});

describe("resolveFlaggedRun — reject path", () => {
  it("writes a compensating negative PointTransaction, sets final_points_awarded=0, recomputes both aggregates", async () => {
    runSelectChain.maybeSingle.mockResolvedValueOnce({ data: flaggedRun({ final_points_awarded: 12 }), error: null });
    txSelectChain.maybeSingle.mockResolvedValueOnce({ data: { season_id: "season-1" }, error: null });
    runUpdateChain.eq.mockResolvedValueOnce({ error: null });
    recomputeUserPointsAggregateMock.mockResolvedValueOnce({ totalPoints: 0, currentLevel: 1 });
    recomputeAndPersistTrustScoreMock.mockResolvedValueOnce(0.9);

    await resolveFlaggedRun("run-1", "rejected", "manual");

    expect(txInsertMock).toHaveBeenCalledWith({
      user_id: "usr-1",
      run_id: "run-1",
      season_id: "season-1",
      amount: -12,
      type: "adjustment",
    });
    const updateArg = runUpdateMock.mock.calls.at(-1)?.[0] as { final_points_awarded: number; status: string };
    expect(updateArg.final_points_awarded).toBe(0);
    expect(updateArg.status).toBe("rejected");
    expect(recomputeUserPointsAggregateMock).toHaveBeenCalledWith("usr-1");
    expect(recomputeAndPersistTrustScoreMock).toHaveBeenCalledWith("usr-1");
  });

  it("skips the compensating transaction when the run already had zero points (nothing to net)", async () => {
    runSelectChain.maybeSingle.mockResolvedValueOnce({ data: flaggedRun({ final_points_awarded: 0 }), error: null });
    runUpdateChain.eq.mockResolvedValueOnce({ error: null });
    recomputeUserPointsAggregateMock.mockResolvedValueOnce({ totalPoints: 0, currentLevel: 1 });
    recomputeAndPersistTrustScoreMock.mockResolvedValueOnce(0.9);

    await resolveFlaggedRun("run-1", "rejected", "manual");

    expect(txInsertMock).not.toHaveBeenCalled();
  });
});

describe("autoResolveOverdueLowConfidenceFlags", () => {
  it("only queries flag_confidence='low' — HIGH-confidence runs are never touched by construction", async () => {
    // Redirect the "run" table's select chain (used for the overdue query, distinct from the by-id fetch
    // used inside resolveFlaggedRun) to runQueryChain for this describe block.
    fromMock.mockImplementation((table: string) => {
      if (table === "run") return { select: runQueryChain.select };
      throw new Error(`unexpected table ${table}`);
    });
    runQueryChain.lt.mockResolvedValueOnce({ data: [], error: null });

    await autoResolveOverdueLowConfidenceFlags(new Date("2026-09-18T00:00:00Z"));

    expect(runQueryChain.eq).toHaveBeenCalledWith("status", "flagged");
    expect(runQueryChain.eq).toHaveBeenCalledWith("flag_confidence", "low");
    const cutoffArg = runQueryChain.lt.mock.calls.at(-1)?.[1] as string;
    expect(new Date(cutoffArg).getTime()).toBe(new Date("2026-09-18T00:00:00Z").getTime() - 48 * 60 * 60 * 1000);
  });
});
