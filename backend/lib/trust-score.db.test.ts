import { describe, expect, it, vi } from "vitest";

const queryChain = {
  select: vi.fn(() => queryChain),
  eq: vi.fn((_col: string, _val: string) => queryChain),
  gte: vi.fn((_col: string, _val: string) => queryChain),
  lte: vi.fn((_col: string, _val: string) => Promise.resolve({ data: [] as unknown[], error: null as unknown })),
};
const updateChain = { eq: vi.fn() };
const updateMock = vi.fn(() => updateChain);
const fromMock = vi.fn((table: string) =>
  table === "run" ? { select: queryChain.select } : { update: updateMock }
);

vi.mock("./supabase", () => ({
  supabaseAdmin: { from: (table: string) => fromMock(table) },
}));

const { trustMultiplierForUser, recomputeAndPersistTrustScore } = await import("./trust-score");

function row(overrides: Partial<{ status: string; flag_confidence: string | null; resolved_via: string | null; anomaly_flags: unknown[] }>) {
  return { status: "validated", flag_confidence: null, resolved_via: null, anomaly_flags: [], ...overrides };
}

describe("trustMultiplierForUser — DB-query level, tech-spec.md §2.4", () => {
  it("queries the rolling 30-day window via created_at gte/lte bounds — no separate cleanup job", async () => {
    queryChain.lte.mockResolvedValueOnce({ data: [], error: null });
    const asOf = new Date("2026-09-18T00:00:00Z");
    await trustMultiplierForUser("usr-1", asOf);

    expect(queryChain.eq).toHaveBeenCalledWith("user_id", "usr-1");
    const gteCallArg = queryChain.gte.mock.calls.at(-1)?.[1] as string;
    const lteCallArg = queryChain.lte.mock.calls.at(-1)?.[1] as string;
    expect(lteCallArg).toBe(asOf.toISOString());
    expect(new Date(gteCallArg).getTime()).toBe(asOf.getTime() - 30 * 24 * 60 * 60 * 1000);
  });

  it("a LOW flag that auto-approved (resolved_via='auto') produces no decay — multiplier stays 1.0", async () => {
    queryChain.lte.mockResolvedValueOnce({
      data: [row({ flag_confidence: "low", status: "approved", resolved_via: "auto" })],
      error: null,
    });
    expect(await trustMultiplierForUser("usr-1")).toBe(1.0);
  });

  it("a LOW flag manually overridden to approved (resolved_via='manual') still decays", async () => {
    queryChain.lte.mockResolvedValueOnce({
      data: [row({ flag_confidence: "low", status: "approved", resolved_via: "manual" })],
      error: null,
    });
    expect(await trustMultiplierForUser("usr-1")).toBeCloseTo(0.95, 10);
  });

  it("a still-pending LOW flag (unresolved) decays — exemption only applies once resolution is known", async () => {
    queryChain.lte.mockResolvedValueOnce({
      data: [row({ flag_confidence: "low", status: "flagged", resolved_via: null })],
      error: null,
    });
    expect(await trustMultiplierForUser("usr-1")).toBeCloseTo(0.95, 10);
  });

  it("an approved run that was previously flagged does not count as a clean run", async () => {
    queryChain.lte.mockResolvedValueOnce({
      data: [row({ flag_confidence: "low", status: "approved", resolved_via: "auto" }), row({ status: "approved" })],
      error: null,
    });
    // Both rows are LOW-flag-history or approved (not validated) — neither is clean, neither decays.
    expect(await trustMultiplierForUser("usr-1")).toBe(1.0);
  });

  it("a validated run with non-empty anomaly_flags does not count as clean", async () => {
    queryChain.lte.mockResolvedValueOnce({
      data: [row({ status: "validated", anomaly_flags: ["pace_cap_exceeded"] })],
      error: null,
    });
    expect(await trustMultiplierForUser("usr-1")).toBe(1.0);
  });

  it("recomputeAndPersistTrustScore writes the computed multiplier to user.trust_score", async () => {
    queryChain.lte.mockResolvedValueOnce({
      data: [row({ flag_confidence: "high" })],
      error: null,
    });
    updateChain.eq.mockResolvedValueOnce({ error: null });
    const result = await recomputeAndPersistTrustScore("usr-1");
    expect(result).toBeCloseTo(0.9, 10);
    expect(updateMock).toHaveBeenCalledWith({ trust_score: result });
    expect(updateChain.eq).toHaveBeenCalledWith("id", "usr-1");
  });
});
