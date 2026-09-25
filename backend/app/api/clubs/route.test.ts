import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();
const isPremiumUserMock = vi.fn();

// `.from("club_member").select(...).eq(...).maybeSingle()` — the existing-membership lookup.
const membershipChain = {
  select: vi.fn(() => membershipChain),
  eq: vi.fn(() => membershipChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: { club_id: string } | null; error: { message: string } | null }> =>
      Promise.resolve({ data: null, error: null })
  ),
};

// `.from("club").insert(...).select(...).single()` — the club insert.
const clubInsertChain = {
  select: vi.fn(() => clubInsertChain),
  single: vi.fn(
    (): Promise<{
      data: {
        id: string;
        name: string;
        description: string | null;
        privacy: string;
        invite_code: string | null;
        created_at: string;
      } | null;
      error: { message: string } | null;
    }> => Promise.resolve({ data: null, error: null })
  ),
};
const clubInsertMock = vi.fn((_row: unknown) => clubInsertChain);

// `.from("club_member").insert(...)` — the owner row.
const memberInsertMock = vi.fn((_row: unknown): Promise<{ error: { message: string } | null }> => Promise.resolve({ error: null }));

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/club/premium", () => ({
  isPremiumUser: (...args: unknown[]) => isPremiumUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: {
    from: (table: string) => {
      if (table === "club_member") return { select: membershipChain.select, insert: memberInsertMock };
      if (table === "club") return { insert: clubInsertMock };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { POST } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };

function postRequest(body: unknown) {
  return new Request("https://example.com/api/clubs", {
    method: "POST",
    headers: { authorization: "Bearer valid-jwt", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/clubs", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    isPremiumUserMock.mockResolvedValue(false);
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await POST(postRequest({ name: "Lari Pagi" }));
    expect(res.status).toBe(401);
    expect(clubInsertMock).not.toHaveBeenCalled();
  });

  it("returns 400 when name is missing", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(postRequest({}));
    expect(res.status).toBe(400);
  });

  it("returns 400 when name exceeds 60 characters", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(postRequest({ name: "x".repeat(61) }));
    expect(res.status).toBe(400);
  });

  it("returns 400 for an invalid privacy value", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(postRequest({ name: "Lari Pagi", privacy: "secret" }));
    expect(res.status).toBe(400);
  });

  it("returns 403 not_premium when the caller isn't Premium — checked before any DB write", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    isPremiumUserMock.mockResolvedValueOnce(false);
    const res = await POST(postRequest({ name: "Lari Pagi" }));
    expect(res.status).toBe(403);
    const json = await res.json();
    expect(json.code).toBe("not_premium");
    expect(membershipChain.select).not.toHaveBeenCalled();
    expect(clubInsertMock).not.toHaveBeenCalled();
  });

  it("returns 409 when the caller is already in a club", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    isPremiumUserMock.mockResolvedValueOnce(true);
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: { club_id: "club-existing" }, error: null });
    const res = await POST(postRequest({ name: "Lari Pagi" }));
    expect(res.status).toBe(409);
    expect(clubInsertMock).not.toHaveBeenCalled();
  });

  it("creates a public club with no invite_code when Premium and not already a member", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    isPremiumUserMock.mockResolvedValueOnce(true);
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    clubInsertChain.single.mockResolvedValueOnce({
      data: {
        id: "club-1",
        name: "Lari Pagi",
        description: null,
        privacy: "public",
        invite_code: null,
        created_at: "2026-09-25T10:00:00Z",
      },
      error: null,
    });

    const res = await POST(postRequest({ name: "  Lari Pagi  " }));
    expect(res.status).toBe(201);
    const json = await res.json();
    expect(json).toEqual({
      club_id: "club-1",
      name: "Lari Pagi",
      description: null,
      privacy: "public",
      invite_code: null,
      created_at: "2026-09-25T10:00:00Z",
    });

    const insertedClub = clubInsertMock.mock.calls.at(-1)?.[0] as { name: string; privacy: string; invite_code: string | null };
    expect(insertedClub.name).toBe("Lari Pagi");
    expect(insertedClub.privacy).toBe("public");
    expect(insertedClub.invite_code).toBeNull();

    const insertedMember = memberInsertMock.mock.calls.at(-1)?.[0] as { user_id: string; club_id: string; role: string };
    expect(insertedMember).toEqual({ user_id: "usr-1", club_id: "club-1", role: "owner" });
  });

  it("generates an 8-character invite_code for an invite_only club", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    isPremiumUserMock.mockResolvedValueOnce(true);
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    clubInsertChain.single.mockResolvedValueOnce({
      data: {
        id: "club-2",
        name: "Elite Runners",
        description: "invite only",
        privacy: "invite_only",
        invite_code: "ABCD1234",
        created_at: "2026-09-25T10:00:00Z",
      },
      error: null,
    });

    await POST(postRequest({ name: "Elite Runners", description: "invite only", privacy: "invite_only" }));

    const insertedClub = clubInsertMock.mock.calls.at(-1)?.[0] as { privacy: string; invite_code: string | null };
    expect(insertedClub.privacy).toBe("invite_only");
    expect(insertedClub.invite_code).toHaveLength(8);
  });

  it("returns 500 when club_member insert fails after the club was created", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    isPremiumUserMock.mockResolvedValueOnce(true);
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    clubInsertChain.single.mockResolvedValueOnce({
      data: {
        id: "club-3",
        name: "Lari Pagi",
        description: null,
        privacy: "public",
        invite_code: null,
        created_at: "2026-09-25T10:00:00Z",
      },
      error: null,
    });
    memberInsertMock.mockResolvedValueOnce({ error: { message: "db error" } });
    const res = await POST(postRequest({ name: "Lari Pagi" }));
    expect(res.status).toBe(500);
  });
});
