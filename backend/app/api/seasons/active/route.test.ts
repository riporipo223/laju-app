import { beforeEach, describe, expect, it, vi } from "vitest";

const requireAuthenticatedIdentityMock = vi.fn();
const maybeSingleMock = vi.fn();
const rpcMock = vi.fn();
const queryChain = {
  select: vi.fn(() => queryChain),
  eq: vi.fn(() => queryChain),
  is: vi.fn(() => queryChain),
  maybeSingle: (...args: unknown[]) => maybeSingleMock(...args),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireAuthenticatedIdentity: (...args: unknown[]) => requireAuthenticatedIdentityMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: { from: () => queryChain, rpc: (...args: unknown[]) => rpcMock(...args) },
}));

const { GET } = await import("./route");

function request() {
  return new Request("https://example.com/api/seasons/active", {
    headers: { authorization: "Bearer valid-jwt" },
  });
}

describe("GET /api/seasons/active", () => {
  // Default for the caller-profile lookup that follows the season read; tests queue the season with mockResolvedValueOnce.
  beforeEach(() => {
    maybeSingleMock.mockReset();
    maybeSingleMock.mockResolvedValue({ data: null, error: null });
  });

  it("rejects unauthenticated requests", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await GET(request());
    expect(res.status).toBe(401);
  });

  it("returns the seeded active season matching database-api-spec.md §2.5's shape", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    maybeSingleMock.mockResolvedValueOnce({
      data: {
        id: "season-uuid-1",
        name: "Season 1 — 2026",
        start_at: "2026-09-01T00:00:00Z",
        end_at: "2026-11-30T23:59:59Z",
        status: "active",
      },
      error: null,
    });
    const res = await GET(request());
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toMatchObject({
      id: "season-uuid-1",
      name: "Season 1 — 2026",
      start_at: "2026-09-01T00:00:00Z",
      end_at: "2026-11-30T23:59:59Z",
      status: "active",
    });
    expect(typeof json.days_remaining).toBe("number");
  });

  it("computes days_remaining from end_at, never negative", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    const farFuture = new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString();
    maybeSingleMock.mockResolvedValueOnce({
      data: { id: "s1", name: "Season X", start_at: "2026-01-01T00:00:00Z", end_at: farFuture, status: "active" },
      error: null,
    });
    const res = await GET(request());
    const json = await res.json();
    expect(json.days_remaining).toBeGreaterThanOrEqual(9);
    expect(json.days_remaining).toBeLessThanOrEqual(10);
  });

  it("clamps days_remaining to zero for an already-past end_at", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    maybeSingleMock.mockResolvedValueOnce({
      data: {
        id: "s1",
        name: "Old Season",
        start_at: "2020-01-01T00:00:00Z",
        end_at: "2020-02-01T00:00:00Z",
        status: "active",
      },
      error: null,
    });
    const res = await GET(request());
    const json = await res.json();
    expect(json.days_remaining).toBe(0);
  });

  it("returns 404 when no active season exists", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    maybeSingleMock.mockResolvedValueOnce({ data: null, error: null });
    const res = await GET(request());
    expect(res.status).toBe(404);
  });

  describe("me (T3.7a)", () => {
    const season = { id: "s1", name: "S", start_at: "2026-01-01T00:00:00Z", end_at: "2099-01-01T00:00:00Z", status: "active" };

    it("returns the caller's season points and league", async () => {
      requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
      maybeSingleMock.mockResolvedValueOnce({ data: season, error: null });
      maybeSingleMock.mockResolvedValueOnce({ data: { id: "user-1" }, error: null });
      rpcMock.mockResolvedValueOnce({ data: 250, error: null });
      const json = await (await GET(request())).json();
      expect(rpcMock).toHaveBeenCalledWith("season_points", { p_user: "user-1", p_season: "s1" });
      expect(json.me).toEqual({ season_points: 250, league: "gold" });
    });

    it("me is null when the caller has no profile yet — the season still loads", async () => {
      requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
      maybeSingleMock.mockResolvedValueOnce({ data: season, error: null });
      maybeSingleMock.mockResolvedValueOnce({ data: null, error: null });
      const res = await GET(request());
      expect(res.status).toBe(200);
      expect((await res.json()).me).toBeNull();
    });

    it("me is null when the points read fails, instead of failing the whole season call", async () => {
      requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
      maybeSingleMock.mockResolvedValueOnce({ data: season, error: null });
      maybeSingleMock.mockResolvedValueOnce({ data: { id: "user-1" }, error: null });
      rpcMock.mockResolvedValueOnce({ data: null, error: { message: "boom" } });
      const res = await GET(request());
      expect(res.status).toBe(200);
      expect((await res.json()).me).toBeNull();
    });
  });
});
