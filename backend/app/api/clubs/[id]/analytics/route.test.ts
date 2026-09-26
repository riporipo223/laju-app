import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();
const isPremiumClubMock = vi.fn();

// `.from("club_member").select("role").eq(...).eq(...).maybeSingle()` — caller-role lookup. Also
// reused for `.select("user_id").eq("club_id", ...)` — the current-member-id list.
const memberChain = {
  select: vi.fn(() => memberChain),
  eq: vi.fn(() => memberChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: { role: string } | null; error: { message: string } | null }> =>
      Promise.resolve({ data: null, error: null })
  ),
  order: vi.fn(
    (): Promise<{ data: { user_id: string }[] | null; error: { message: string } | null }> =>
      Promise.resolve({ data: [], error: null })
  ),
};

// `.from("run").select(...).in(...).in(...).gte(...).gte(...)` — the qualifying-run fetch.
const runChain = {
  select: vi.fn(() => runChain),
  in: vi.fn(() => runChain),
  gte: vi.fn(() => runChain),
  order: vi.fn(
    (): Promise<{
      data: { user_id: string; distance_meters: number; final_points_awarded: number | null }[] | null;
      error: { message: string } | null;
    }> => Promise.resolve({ data: [], error: null })
  ),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/club-war/premium", () => ({
  isPremiumClub: (...args: unknown[]) => isPremiumClubMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: {
    from: (table: string) => {
      if (table === "club_member") return { select: memberChain.select };
      if (table === "run") return { select: runChain.select };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { GET } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };
const params = () => Promise.resolve({ id: "club-1" });

function getRequest() {
  return new Request("https://example.com/api/clubs/club-1/analytics", { headers: { authorization: "Bearer valid-jwt" } });
}

describe("GET /api/clubs/[id]/analytics", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    isPremiumClubMock.mockResolvedValue(true);
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await GET(getRequest(), { params: params() });
    expect(res.status).toBe(401);
  });

  it("returns 403 when the caller is neither owner nor admin", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    memberChain.maybeSingle.mockResolvedValueOnce({ data: { role: "member" }, error: null });
    const res = await GET(getRequest(), { params: params() });
    expect(res.status).toBe(403);
  });

  it("returns 403 not_premium_club when the Circle isn't a Premium Club", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    memberChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    isPremiumClubMock.mockResolvedValueOnce(false);
    const res = await GET(getRequest(), { params: params() });
    expect(res.status).toBe(403);
    const json = await res.json();
    expect(json.error).toBe("not_premium_club");
  });

  it("returns the aggregate totals, active member count, and top contributors", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    memberChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    memberChain.order.mockResolvedValueOnce({ data: [{ user_id: "usr-1" }, { user_id: "usr-2" }], error: null });
    runChain.order.mockResolvedValueOnce({
      data: [
        { user_id: "usr-1", distance_meters: 3000, final_points_awarded: 6 },
        { user_id: "usr-2", distance_meters: 9000, final_points_awarded: 18 },
      ],
      error: null,
    });
    const res = await GET(getRequest(), { params: params() });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({
      total_distance_meters: 12000,
      total_points: 24,
      active_member_count: 2,
      top_contributors: [
        { user_id: "usr-2", distance_meters: 9000, points: 18 },
        { user_id: "usr-1", distance_meters: 3000, points: 6 },
      ],
    });
  });

  it("returns all zeros without querying runs when the Circle has no current members", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    memberChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    memberChain.order.mockResolvedValueOnce({ data: [], error: null });
    const res = await GET(getRequest(), { params: params() });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({ total_distance_meters: 0, total_points: 0, active_member_count: 0, top_contributors: [] });
    expect(runChain.select).not.toHaveBeenCalled();
  });
});
