import { describe, expect, it, vi } from "vitest";

const requireAuthenticatedIdentityMock = vi.fn();
const maybeSingleMock = vi.fn();
const queryChain = {
  select: vi.fn(() => queryChain),
  eq: vi.fn(() => queryChain),
  maybeSingle: (...args: unknown[]) => maybeSingleMock(...args),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireAuthenticatedIdentity: (...args: unknown[]) => requireAuthenticatedIdentityMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: { from: () => queryChain },
}));

const { GET } = await import("./route");

function request() {
  return new Request("https://example.com/api/seasons/active", {
    headers: { authorization: "Bearer valid-jwt" },
  });
}

describe("GET /api/seasons/active", () => {
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
});
