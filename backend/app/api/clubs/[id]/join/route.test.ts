import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();
const isPremiumClubMock = vi.fn();

// `.from("club").select(...).eq(...).maybeSingle()` — the club lookup (privacy + invite_code).
const clubChain = {
  select: vi.fn(() => clubChain),
  eq: vi.fn(() => clubChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: { id: string; privacy: string; invite_code: string | null } | null; error: { message: string } | null }> =>
      Promise.resolve({ data: null, error: null })
  ),
};

// `.from("club_member").select(...).eq(...).maybeSingle()` — the existing-membership lookup.
// `.from("club_member").insert(...)` — the join insert.
const membershipChain = {
  select: vi.fn(() => membershipChain),
  eq: vi.fn(() => membershipChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: { club_id: string } | null; error: { message: string } | null }> =>
      Promise.resolve({ data: null, error: null })
  ),
};
const memberInsertMock = vi.fn((_row: unknown): Promise<{ error: { message: string } | null }> => Promise.resolve({ error: null }));

// `.from("club_membership_history").insert(...)` — opens the joiner's own membership stint.
const membershipHistoryInsertMock = vi.fn(
  (_row: unknown): Promise<{ error: { message: string } | null }> => Promise.resolve({ error: null })
);

// `.from("club_member").select("*", { count: "exact", head: true }).eq("club_id", ...)` — the member
// count for the cap check (product-spec.md §4.24 AC22). A distinct chain from `membershipChain` even
// though both hang off the same `.from("club_member")` — Supabase's own count-query shape (`.eq()`
// itself resolves to `{count, error}`, no `.maybeSingle()`) rather than the row-lookup shape.
const countChain = {
  eq: vi.fn((): Promise<{ count: number | null; error: { message: string } | null }> => Promise.resolve({ count: 0, error: null })),
};
// `select("*", { count: "exact", head: true })` (2 args, options with `count`) routes to `countChain`;
// `select("club_id")` (1 arg) routes to the existing `membershipChain` — same dispatcher distinguishing
// by call shape, not a second `.from("club_member")` mock.
const clubMemberSelectMock = vi.fn((...args: unknown[]) => {
  const options = args[1] as { count?: string } | undefined;
  if (options?.count) return countChain;
  return membershipChain;
});

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
      if (table === "club") return { select: clubChain.select };
      if (table === "club_member") return { select: clubMemberSelectMock, insert: memberInsertMock };
      if (table === "club_membership_history") return { insert: membershipHistoryInsertMock };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { POST } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };
const params = () => Promise.resolve({ id: "club-1" });

function postRequest(body: unknown) {
  return new Request("https://example.com/api/clubs/club-1/join", {
    method: "POST",
    headers: { authorization: "Bearer valid-jwt", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/clubs/[id]/join", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    isPremiumClubMock.mockResolvedValue(false);
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await POST(postRequest({}), { params: params() });
    expect(res.status).toBe(401);
    expect(memberInsertMock).not.toHaveBeenCalled();
  });

  it("returns 404 when the club doesn't exist", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    clubChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await POST(postRequest({}), { params: params() });
    expect(res.status).toBe(404);
  });

  it("returns 409 when the caller is already in a club", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    clubChain.maybeSingle.mockResolvedValueOnce({ data: { id: "club-1", privacy: "public", invite_code: null }, error: null });
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: { club_id: "club-other" }, error: null });
    const res = await POST(postRequest({}), { params: params() });
    expect(res.status).toBe(409);
    expect(memberInsertMock).not.toHaveBeenCalled();
  });

  it("joins a public club without needing an invite code", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    clubChain.maybeSingle.mockResolvedValueOnce({ data: { id: "club-1", privacy: "public", invite_code: null }, error: null });
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await POST(postRequest({}), { params: params() });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({ club_id: "club-1", joined: true });
    const insertedRow = memberInsertMock.mock.calls.at(-1)?.[0] as { user_id: string; club_id: string; role: string };
    expect(insertedRow).toEqual({ user_id: "usr-1", club_id: "club-1", role: "member" });

    const insertedHistory = membershipHistoryInsertMock.mock.calls.at(-1)?.[0] as {
      club_id: string;
      user_id: string;
    };
    expect(insertedHistory.club_id).toBe("club-1");
    expect(insertedHistory.user_id).toBe("usr-1");
  });

  it("returns 403 when joining an invite_only club with no invite code", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    clubChain.maybeSingle.mockResolvedValueOnce({ data: { id: "club-1", privacy: "invite_only", invite_code: "ABCD1234" }, error: null });
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await POST(postRequest({}), { params: params() });
    expect(res.status).toBe(403);
    expect(memberInsertMock).not.toHaveBeenCalled();
  });

  it("returns 403 when the invite code doesn't match", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    clubChain.maybeSingle.mockResolvedValueOnce({ data: { id: "club-1", privacy: "invite_only", invite_code: "ABCD1234" }, error: null });
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await POST(postRequest({ invite_code: "WRONGCOD" }), { params: params() });
    expect(res.status).toBe(403);
    expect(memberInsertMock).not.toHaveBeenCalled();
  });

  it("joins an invite_only club when the invite code matches, case-insensitively", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    clubChain.maybeSingle.mockResolvedValueOnce({ data: { id: "club-1", privacy: "invite_only", invite_code: "ABCD1234" }, error: null });
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await POST(postRequest({ invite_code: "abcd1234" }), { params: params() });
    expect(res.status).toBe(200);
    expect(memberInsertMock).toHaveBeenCalled();
  });

  it("returns 500 when the insert fails", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    clubChain.maybeSingle.mockResolvedValueOnce({ data: { id: "club-1", privacy: "public", invite_code: null }, error: null });
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    memberInsertMock.mockResolvedValueOnce({ error: { message: "db error" } });
    const res = await POST(postRequest({}), { params: params() });
    expect(res.status).toBe(500);
  });

  describe("member cap (product-spec.md §4.24 AC22)", () => {
    it("joins a Free Circle below its 20-member cap", async () => {
      requireUserMock.mockResolvedValueOnce({ user: completeUser });
      clubChain.maybeSingle.mockResolvedValueOnce({ data: { id: "club-1", privacy: "public", invite_code: null }, error: null });
      membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
      countChain.eq.mockResolvedValueOnce({ count: 19, error: null });
      const res = await POST(postRequest({}), { params: params() });
      expect(res.status).toBe(200);
      expect(memberInsertMock).toHaveBeenCalled();
    });

    it("rejects joining a Free Circle exactly at its 20-member cap", async () => {
      requireUserMock.mockResolvedValueOnce({ user: completeUser });
      clubChain.maybeSingle.mockResolvedValueOnce({ data: { id: "club-1", privacy: "public", invite_code: null }, error: null });
      membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
      countChain.eq.mockResolvedValueOnce({ count: 20, error: null });
      const res = await POST(postRequest({}), { params: params() });
      expect(res.status).toBe(409);
      const json = await res.json();
      expect(json.code).toBe("circle_full");
      expect(memberInsertMock).not.toHaveBeenCalled();
    });

    it("still joins a Premium Circle's owner past 20, up to its 100-member cap", async () => {
      requireUserMock.mockResolvedValueOnce({ user: completeUser });
      clubChain.maybeSingle.mockResolvedValueOnce({ data: { id: "club-1", privacy: "public", invite_code: null }, error: null });
      membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
      isPremiumClubMock.mockResolvedValueOnce(true);
      countChain.eq.mockResolvedValueOnce({ count: 99, error: null });
      const res = await POST(postRequest({}), { params: params() });
      expect(res.status).toBe(200);
      expect(memberInsertMock).toHaveBeenCalled();
    });

    it("rejects joining a Premium Circle exactly at its 100-member cap", async () => {
      requireUserMock.mockResolvedValueOnce({ user: completeUser });
      clubChain.maybeSingle.mockResolvedValueOnce({ data: { id: "club-1", privacy: "public", invite_code: null }, error: null });
      membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
      isPremiumClubMock.mockResolvedValueOnce(true);
      countChain.eq.mockResolvedValueOnce({ count: 100, error: null });
      const res = await POST(postRequest({}), { params: params() });
      expect(res.status).toBe(409);
      const json = await res.json();
      expect(json.code).toBe("circle_full");
      expect(memberInsertMock).not.toHaveBeenCalled();
    });
  });
});
