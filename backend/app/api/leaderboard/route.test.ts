import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();

interface Result {
  data: unknown;
  error: { message: string } | null;
}

let seasonResult: Result;
let scopeResult: Result;
let entriesResult: Result;
let meResult: Result;
const calls: { table: string; op: string; args: unknown[] }[] = [];

interface Chain {
  select: (columns: string) => Chain;
  eq: (column: string, value: string) => Chain;
  order: (column: string, options: { ascending: boolean }) => Chain;
  limit: (count: number) => Promise<Result>;
  maybeSingle: () => Promise<Result>;
}

function makeChain(table: string): Chain {
  let columns = "";
  const chain: Chain = {
    select: (selected) => {
      columns = selected;
      return chain;
    },
    eq: (column, value) => {
      calls.push({ table, op: "eq", args: [column, value] });
      return chain;
    },
    order: (column, options) => {
      calls.push({ table, op: "order", args: [column, options] });
      return chain;
    },
    limit: (count) => {
      calls.push({ table, op: "limit", args: [count] });
      return Promise.resolve(entriesResult);
    },
    maybeSingle: () => {
      if (table === "season") return Promise.resolve(seasonResult);
      if (table === "leaderboard_scope") return Promise.resolve(scopeResult);
      return Promise.resolve(columns === "rank, points" ? meResult : entriesResult);
    },
  };
  return chain;
}

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: { from: (table: string) => makeChain(table) },
}));

const { GET } = await import("./route");

const SEASON_ID = "0a23423a-20b4-4b86-a65f-4d73097112f6";

function request(query = "scope=global") {
  return new Request(`https://example.com/api/leaderboard?${query}`, { headers: { authorization: "Bearer jwt" } });
}

describe("GET /api/leaderboard", () => {
  beforeEach(() => {
    calls.length = 0;
    requireUserMock.mockReset();
    requireUserMock.mockResolvedValue({ user: { id: "usr-me" } });
    seasonResult = { data: { id: SEASON_ID }, error: null };
    scopeResult = { data: { computed_at: "2026-09-18T20:15:00.267944+00:00", insufficient_data: false }, error: null };
    entriesResult = {
      data: [
        { rank: 1, user_id: "usr-88", frozen_display_name: "andi_r", points: 4200 },
        { rank: 2, user_id: "usr-123", frozen_display_name: "budi_run", points: 3980 },
      ],
      error: null,
    };
    meResult = { data: { rank: 47, points: 1240 }, error: null };
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    expect((await GET(request())).status).toBe(401);
  });

  it("matches database-api-spec.md §2.4's response shape (entries, me, computed_at)", async () => {
    const res = await GET(request());
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      season_id: SEASON_ID,
      scope: "global",
      scope_id: null,
      computed_at: "2026-09-18T20:15:00.267944+00:00",
      insufficient_data: false,
      entries: [
        { rank: 1, user_id: "usr-88", username: "andi_r", points: 4200 },
        { rank: 2, user_id: "usr-123", username: "budi_run", points: 3980 },
      ],
      me: { rank: 47, points: 1240 },
    });
  });

  it("me is null when the caller is not on the board", async () => {
    meResult = { data: null, error: null };
    expect((await (await GET(request())).json()).me).toBeNull();
  });

  it("returns an empty board (not an error) before the job has ever run", async () => {
    scopeResult = { data: null, error: null };
    entriesResult = { data: [], error: null };
    meResult = { data: null, error: null };
    const json = await (await GET(request())).json();
    expect(json).toMatchObject({ entries: [], me: null, computed_at: null, insufficient_data: false });
  });

  it("reads the precomputed tables ordered by points desc, default limit 50, scoped to the caller for `me`", async () => {
    await GET(request());
    expect(calls).toContainEqual({ table: "leaderboard_entry", op: "order", args: ["points", { ascending: false }] });
    expect(calls).toContainEqual({ table: "leaderboard_entry", op: "limit", args: [50] });
    expect(calls).toContainEqual({ table: "leaderboard_entry", op: "eq", args: ["user_id", "usr-me"] });
    expect(calls.some((call) => call.table === "point_transaction")).toBe(false); // never a live aggregation
  });

  it("honours limit and an explicit season_id", async () => {
    const other = "11111111-2222-4333-8444-555555555555";
    await GET(request(`scope=global&limit=10&season_id=${other}`));
    expect(calls).toContainEqual({ table: "leaderboard_entry", op: "limit", args: [10] });
    expect(calls).toContainEqual({ table: "leaderboard_entry", op: "eq", args: ["season_id", other] });
    expect(calls.some((call) => call.table === "season")).toBe(false); // no active-season lookup needed
  });

  it.each([
    ["missing scope", ""],
    ["unknown scope", "scope=galaxy"],
    ["region scope (T3.4, not built)", "scope=provinsi&scope_id=DKI"],
    ["limit 0", "scope=global&limit=0"],
    ["limit above the cap", "scope=global&limit=101"],
    ["non-numeric limit", "scope=global&limit=abc"],
    ["fractional limit", "scope=global&limit=2.5"],
    ["non-UUID season_id", "scope=global&season_id=season_2026_q3"],
  ])("400s on %s", async (_label, query) => {
    expect((await GET(request(query))).status).toBe(400);
  });

  it("404s when there is no active season and none was requested", async () => {
    seasonResult = { data: null, error: null };
    expect((await GET(request())).status).toBe(404);
  });

  it("500s when a read fails", async () => {
    entriesResult = { data: null, error: { message: "boom" } };
    expect((await GET(request())).status).toBe(500);
  });
});
