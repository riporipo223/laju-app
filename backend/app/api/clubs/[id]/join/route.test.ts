import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();

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

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: {
    from: (table: string) => {
      if (table === "club") return { select: clubChain.select };
      if (table === "club_member") return { select: membershipChain.select, insert: memberInsertMock };
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
});
