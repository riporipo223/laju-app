import { describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();
const singleMock = vi.fn();
const queryChain = {
  select: vi.fn(() => queryChain),
  eq: vi.fn(() => queryChain),
  single: (...args: unknown[]) => singleMock(...args),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: { from: () => queryChain },
}));

const { GET } = await import("./route");

function request() {
  return new Request("https://example.com/api/users/me/progress", {
    headers: { authorization: "Bearer valid-jwt" },
  });
}

describe("GET /api/users/me/progress", () => {
  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await GET(request());
    expect(res.status).toBe(401);
  });

  it("matches database-api-spec.md §2.3's example shape", async () => {
    requireUserMock.mockResolvedValueOnce({ user: { id: "usr-1" } });
    singleMock.mockResolvedValueOnce({
      data: { total_points: 1240, current_level: 6, trust_score: 0.98 },
      error: null,
    });
    const res = await GET(request());
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({
      total_points: 1240,
      current_level: 6,
      points_to_next_level: 260, // derived from total_points via pointsToNextLevel: level-5 threshold 1500 - 1240
      trust_score: 0.98,
    });
  });

  it("scopes the query to the authenticated caller's own user_id", async () => {
    requireUserMock.mockResolvedValueOnce({ user: { id: "usr-second" } });
    singleMock.mockResolvedValueOnce({ data: { total_points: 0, current_level: 1, trust_score: 1.0 }, error: null });
    await GET(request());
    expect(queryChain.eq).toHaveBeenLastCalledWith("id", "usr-second");
  });

  it("returns 500 when the user row cannot be loaded", async () => {
    requireUserMock.mockResolvedValueOnce({ user: { id: "usr-1" } });
    singleMock.mockResolvedValueOnce({ data: null, error: { message: "boom" } });
    const res = await GET(request());
    expect(res.status).toBe(500);
  });

  it("points_to_next_level is 0 at the top level, not negative", async () => {
    requireUserMock.mockResolvedValueOnce({ user: { id: "usr-1" } });
    singleMock.mockResolvedValueOnce({
      data: { total_points: 999999, current_level: 8, trust_score: 1.0 },
      error: null,
    });
    const res = await GET(request());
    const json = await res.json();
    expect(json.points_to_next_level).toBe(0);
  });
});
