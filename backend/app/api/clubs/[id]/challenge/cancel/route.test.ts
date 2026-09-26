import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();

// `.from("club_member").select("role").eq(...).eq(...).maybeSingle()` — the caller-role lookup.
const roleChain = {
  select: vi.fn(() => roleChain),
  eq: vi.fn(() => roleChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: { role: string } | null; error: { message: string } | null }> =>
      Promise.resolve({ data: null, error: null })
  ),
};

// `.from("club_challenge").select("id").eq(...).in(...).maybeSingle()` — the open-challenge lookup.
const openChallengeChain = {
  select: vi.fn(() => openChallengeChain),
  eq: vi.fn(() => openChallengeChain),
  in: vi.fn(() => openChallengeChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: { id: string } | null; error: { message: string } | null }> => Promise.resolve({ data: null, error: null })
  ),
};

// `.from("club_challenge").update({status, cancelled_at}).eq("id", ...)` — the cancel write.
const updateChain = {
  update: vi.fn((_fields: unknown) => updateChain),
  eq: vi.fn((): Promise<{ error: { message: string } | null }> => Promise.resolve({ error: null })),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: {
    from: (table: string) => {
      if (table === "club_member") return { select: roleChain.select };
      if (table === "club_challenge") return { select: openChallengeChain.select, update: updateChain.update };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { DELETE } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };
const params = () => Promise.resolve({ id: "club-1" });

function deleteRequest() {
  return new Request("https://example.com/api/clubs/club-1/challenge/cancel", {
    method: "DELETE",
    headers: { authorization: "Bearer valid-jwt" },
  });
}

describe("DELETE /api/clubs/[id]/challenge/cancel", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(401);
  });

  it("returns 403 when the caller is an admin, not the owner", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "admin" }, error: null });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(403);
    expect(updateChain.update).not.toHaveBeenCalled();
  });

  it("returns 403 when the caller is a plain member", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "member" }, error: null });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(403);
  });

  it("returns 404 when there is no open challenge to cancel", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    openChallengeChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(404);
    expect(updateChain.update).not.toHaveBeenCalled();
  });

  it("cancels the open challenge when the caller is owner", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    openChallengeChain.maybeSingle.mockResolvedValueOnce({ data: { id: "challenge-1" }, error: null });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({ challenge_id: "challenge-1", cancelled: true });
    const updatedFields = updateChain.update.mock.calls.at(-1)?.[0] as { status: string; cancelled_at: unknown };
    expect(updatedFields.status).toBe("cancelled");
    expect(updatedFields.cancelled_at).toBeTruthy();
    expect(updateChain.eq).toHaveBeenCalledWith("id", "challenge-1");
  });

  it("returns 500 when the cancel write fails", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    openChallengeChain.maybeSingle.mockResolvedValueOnce({ data: { id: "challenge-1" }, error: null });
    updateChain.eq.mockResolvedValueOnce({ error: { message: "db error" } });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(500);
  });
});
