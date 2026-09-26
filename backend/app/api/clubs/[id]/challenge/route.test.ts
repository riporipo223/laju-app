import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();
const isPremiumClubMock = vi.fn();

// `.from("club_member").select("role").eq(...).eq(...).maybeSingle()` — the caller-role lookup.
const roleChain = {
  select: vi.fn(() => roleChain),
  eq: vi.fn(() => roleChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: { role: string } | null; error: { message: string } | null }> =>
      Promise.resolve({ data: null, error: null })
  ),
};

// `.from("club_challenge").select("id").eq(...).in(...).maybeSingle()` — the existing-open-challenge check.
const existingChain = {
  select: vi.fn(() => existingChain),
  eq: vi.fn(() => existingChain),
  in: vi.fn(() => existingChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: { id: string } | null; error: { message: string } | null }> => Promise.resolve({ data: null, error: null })
  ),
};

// `.from("club_challenge").insert(...).select(...).single()` — the create insert.
const insertChain = {
  select: vi.fn(() => insertChain),
  single: vi.fn(
    (): Promise<{
      data: {
        id: string;
        club_id: string;
        name: string;
        target_type: string;
        target_value: number;
        deadline: string;
        status: string;
        created_at: string;
      } | null;
      error: { message: string } | null;
    }> => Promise.resolve({ data: null, error: null })
  ),
};
const insertMock = vi.fn((_row: unknown) => insertChain);

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
      if (table === "club_member") return { select: roleChain.select };
      if (table === "club_challenge") return { select: existingChain.select, insert: insertMock };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { POST } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };
const params = () => Promise.resolve({ id: "club-1" });
const futureDeadline = new Date(Date.now() + 1000 * 60 * 60 * 24 * 30).toISOString();

function postRequest(body: unknown) {
  return new Request("https://example.com/api/clubs/club-1/challenge", {
    method: "POST",
    headers: { authorization: "Bearer valid-jwt", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/clubs/[id]/challenge", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    isPremiumClubMock.mockResolvedValue(true);
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await POST(postRequest({}), { params: params() });
    expect(res.status).toBe(401);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("returns 403 when the caller is neither owner nor admin", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "member" }, error: null });
    const res = await POST(
      postRequest({ name: "500km bareng", target_type: "distance", target_value: 500000, deadline: futureDeadline }),
      { params: params() }
    );
    expect(res.status).toBe(403);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("returns 403 not_premium_club when the Circle isn't a Premium Club", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    isPremiumClubMock.mockResolvedValueOnce(false);
    const res = await POST(
      postRequest({ name: "500km bareng", target_type: "distance", target_value: 500000, deadline: futureDeadline }),
      { params: params() }
    );
    expect(res.status).toBe(403);
    const json = await res.json();
    expect(json.error).toBe("not_premium_club");
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("returns 400 when name is missing", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    const res = await POST(postRequest({ target_type: "distance", target_value: 500000, deadline: futureDeadline }), {
      params: params(),
    });
    expect(res.status).toBe(400);
  });

  it("returns 400 for an invalid target_type", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    const res = await POST(
      postRequest({ name: "500km bareng", target_type: "speed", target_value: 500000, deadline: futureDeadline }),
      { params: params() }
    );
    expect(res.status).toBe(400);
  });

  it("returns 400 when target_value is not positive", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    const res = await POST(
      postRequest({ name: "500km bareng", target_type: "distance", target_value: 0, deadline: futureDeadline }),
      { params: params() }
    );
    expect(res.status).toBe(400);
  });

  it("returns 400 when the deadline is in the past", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    const res = await POST(
      postRequest({
        name: "500km bareng",
        target_type: "distance",
        target_value: 500000,
        deadline: "2020-01-01T00:00:00Z",
      }),
      { params: params() }
    );
    expect(res.status).toBe(400);
  });

  it("returns 409 when the Circle already has an open challenge", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "admin" }, error: null });
    existingChain.maybeSingle.mockResolvedValueOnce({ data: { id: "challenge-existing" }, error: null });
    const res = await POST(
      postRequest({ name: "500km bareng", target_type: "distance", target_value: 500000, deadline: futureDeadline }),
      { params: params() }
    );
    expect(res.status).toBe(409);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("creates a challenge when the caller is owner, the Circle is Premium, and no challenge is open", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    existingChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    insertChain.single.mockResolvedValueOnce({
      data: {
        id: "challenge-1",
        club_id: "club-1",
        name: "500km bareng",
        target_type: "distance",
        target_value: 500000,
        deadline: futureDeadline,
        status: "active",
        created_at: "2026-09-26T10:00:00Z",
      },
      error: null,
    });
    const res = await POST(
      postRequest({ name: "500km bareng", target_type: "distance", target_value: 500000, deadline: futureDeadline }),
      { params: params() }
    );
    expect(res.status).toBe(201);
    const json = await res.json();
    expect(json).toEqual({
      challenge_id: "challenge-1",
      club_id: "club-1",
      name: "500km bareng",
      target_type: "distance",
      target_value: 500000,
      deadline: futureDeadline,
      status: "active",
      created_at: "2026-09-26T10:00:00Z",
    });
  });

  it("returns 500 when the insert fails", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    roleChain.maybeSingle.mockResolvedValueOnce({ data: { role: "owner" }, error: null });
    existingChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    insertChain.single.mockResolvedValueOnce({ data: null, error: { message: "db error" } });
    const res = await POST(
      postRequest({ name: "500km bareng", target_type: "distance", target_value: 500000, deadline: futureDeadline }),
      { params: params() }
    );
    expect(res.status).toBe(500);
  });
});
