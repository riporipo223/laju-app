import { describe, expect, it, vi } from "vitest";

const seasonChain = { select: vi.fn(() => seasonChain), eq: vi.fn(() => seasonChain), maybeSingle: vi.fn() };
const insertMock = vi.fn((_row: unknown) => Promise.resolve({ error: null as { message: string } | null }));
const sumChain = { select: vi.fn(() => sumChain), eq: vi.fn() };
const updateChain = { eq: vi.fn() };
const updateMock = vi.fn((_row: unknown) => updateChain);

const fromMock = vi.fn((table: string) => {
  if (table === "season") return seasonChain;
  if (table === "point_transaction") return { insert: insertMock, select: sumChain.select };
  if (table === "user") return { update: updateMock };
  throw new Error(`unexpected table ${table}`);
});

vi.mock("./supabase", () => ({ supabaseAdmin: { from: (table: string) => fromMock(table) } }));

const { recordRunPointsAndUpdateAggregate, NoActiveSeasonError } = await import("./point-transaction");

describe("recordRunPointsAndUpdateAggregate", () => {
  it("throws NoActiveSeasonError when no active season exists — never writes a PointTransaction without one", async () => {
    seasonChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    await expect(recordRunPointsAndUpdateAggregate("usr-1", "run-1", 50)).rejects.toThrow(NoActiveSeasonError);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("writes a PointTransaction referencing the active season's id, type='run'", async () => {
    seasonChain.maybeSingle.mockResolvedValueOnce({ data: { id: "season-abc" }, error: null });
    insertMock.mockResolvedValueOnce({ error: null });
    sumChain.eq.mockResolvedValueOnce({ data: [{ amount: 50 }], error: null });
    updateChain.eq.mockResolvedValueOnce({ error: null });

    await recordRunPointsAndUpdateAggregate("usr-1", "run-1", 50);

    expect(insertMock).toHaveBeenCalledWith({
      user_id: "usr-1",
      run_id: "run-1",
      season_id: "season-abc",
      amount: 50,
      type: "run",
    });
  });

  it("recomputes total_points as the SUM of the user's ledger, not an increment", async () => {
    seasonChain.maybeSingle.mockResolvedValueOnce({ data: { id: "season-abc" }, error: null });
    insertMock.mockResolvedValueOnce({ error: null });
    // Ledger already has 2 prior rows (30, 20) plus this new one (50) = 100 total.
    sumChain.eq.mockResolvedValueOnce({ data: [{ amount: 30 }, { amount: 20 }, { amount: 50 }], error: null });
    updateChain.eq.mockResolvedValueOnce({ error: null });

    const result = await recordRunPointsAndUpdateAggregate("usr-1", "run-1", 50);

    expect(result.totalPoints).toBe(100);
    expect(result.currentLevel).toBe(2); // 100 points crosses the level-2 threshold
    expect(updateMock).toHaveBeenCalledWith({ total_points: 100, current_level: 2 });
    expect(updateChain.eq).toHaveBeenCalledWith("id", "usr-1");
  });
});
