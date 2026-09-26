import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();

// `.from("club_member").select(...).eq(...).order(...)` — the member list query. Also reused for the
// kick-member caller-role lookup (`.select("role").eq("user_id", ...).eq("club_id", ...).maybeSingle()`)
// — same underlying `.from("club_member")` builder, just a different terminal call.
const listChain = {
  select: vi.fn(() => listChain),
  eq: vi.fn(() => listChain),
  order: vi.fn((): Promise<{ data: unknown[] | null; error: { message: string } | null }> => Promise.resolve({ data: [], error: null })),
  maybeSingle: vi.fn(
    (): Promise<{ data: { role: string } | null; error: { message: string } | null }> =>
      Promise.resolve({ data: null, error: null })
  ),
};

// `.from("club_member").delete().eq(...).eq(...).select(...).maybeSingle()` — self-leave.
const deleteChain = {
  delete: vi.fn(() => deleteChain),
  eq: vi.fn(() => deleteChain),
  select: vi.fn(() => deleteChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: { club_id: string } | null; error: { message: string } | null }> =>
      Promise.resolve({ data: null, error: null })
  ),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: {
    from: (table: string) => {
      if (table === "club_member") return { select: listChain.select, delete: deleteChain.delete };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { GET, DELETE } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };
const params = () => Promise.resolve({ id: "club-1" });

function getRequest() {
  return new Request("https://example.com/api/clubs/club-1/members", { headers: { authorization: "Bearer valid-jwt" } });
}

function deleteRequest(body?: { user_id: string }) {
  return new Request("https://example.com/api/clubs/club-1/members", {
    method: "DELETE",
    headers: { authorization: "Bearer valid-jwt", "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
}

describe("GET /api/clubs/[id]/members", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await GET(getRequest(), { params: params() });
    expect(res.status).toBe(401);
  });

  it("returns the club's members, joined-oldest-first", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    listChain.order.mockResolvedValueOnce({
      data: [
        {
          user_id: "usr-2",
          role: "owner",
          joined_at: "2026-09-25T10:00:00Z",
          user: { username: "budi_run", display_name: "Budi", avatar_url: null },
        },
      ],
      error: null,
    });
    const res = await GET(getRequest(), { params: params() });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({
      members: [
        {
          user_id: "usr-2",
          username: "budi_run",
          display_name: "Budi",
          avatar_url: null,
          role: "owner",
          joined_at: "2026-09-25T10:00:00Z",
        },
      ],
    });
    expect(listChain.order).toHaveBeenCalledWith("joined_at", { ascending: true });
  });

  it("returns 500 when the query fails", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    listChain.order.mockResolvedValueOnce({ data: null, error: { message: "db error" } });
    const res = await GET(getRequest(), { params: params() });
    expect(res.status).toBe(500);
  });
});

describe("DELETE /api/clubs/[id]/members (self-leave)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(401);
    expect(deleteChain.delete).not.toHaveBeenCalled();
  });

  it("removes the caller's own membership", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    deleteChain.maybeSingle.mockResolvedValueOnce({ data: { club_id: "club-1" }, error: null });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({ club_id: "club-1", left: true });
    expect(deleteChain.eq).toHaveBeenCalledWith("user_id", "usr-1");
    expect(deleteChain.eq).toHaveBeenCalledWith("club_id", "club-1");
  });

  it("returns 404 when the caller isn't a member of that club", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    deleteChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(404);
  });
});

describe("DELETE /api/clubs/[id]/members (kick-member, product-spec.md §4.24 AC23)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 403 when the caller is neither owner nor admin", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    listChain.maybeSingle.mockResolvedValueOnce({ data: { role: "member" }, error: null });
    const res = await DELETE(deleteRequest({ user_id: "usr-2" }), { params: params() });
    expect(res.status).toBe(403);
    expect(deleteChain.delete).not.toHaveBeenCalled();
  });

  it("kicks a regular member when the caller is owner", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    listChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    deleteChain.maybeSingle.mockResolvedValueOnce({ data: { club_id: "club-1" }, error: null });
    const res = await DELETE(deleteRequest({ user_id: "usr-2" }), { params: params() });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({ club_id: "club-1", kicked_user_id: "usr-2", kicked: true });
    expect(deleteChain.eq).toHaveBeenCalledWith("user_id", "usr-2");
    expect(deleteChain.eq).toHaveBeenCalledWith("club_id", "club-1");
  });

  it("kicks a regular member when the caller is admin, not just owner", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    listChain.maybeSingle.mockResolvedValueOnce({ data: { role: "admin" }, error: null });
    deleteChain.maybeSingle.mockResolvedValueOnce({ data: { club_id: "club-1" }, error: null });
    const res = await DELETE(deleteRequest({ user_id: "usr-2" }), { params: params() });
    expect(res.status).toBe(200);
  });

  it("rejects kicking yourself — not free, per AC16's separate leave/transfer path", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await DELETE(deleteRequest({ user_id: "usr-1" }), { params: params() });
    expect(res.status).toBe(400);
    expect(listChain.maybeSingle).not.toHaveBeenCalled();
    expect(deleteChain.delete).not.toHaveBeenCalled();
  });

  it("returns 404 when the target isn't a member of the club", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    listChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    deleteChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await DELETE(deleteRequest({ user_id: "usr-ghost" }), { params: params() });
    expect(res.status).toBe(404);
  });
});
