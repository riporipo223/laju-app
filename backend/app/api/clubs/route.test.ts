import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();

// `.from("club_member")` — shared by POST's `.select().eq().maybeSingle()` membership lookup and GET's
// `.select().in()` batched member-count lookup. One chain (real supabase-js also returns one query
// builder object per `.from()` call that both patterns build on).
const membershipChain = {
  select: vi.fn(() => membershipChain),
  eq: vi.fn(() => membershipChain),
  in: vi.fn(
    (): Promise<{ data: { club_id: string }[] | null; error: { message: string } | null }> =>
      Promise.resolve({ data: [], error: null })
  ),
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

// `.from("club_membership_history").insert(...)` — opens the owner's own membership stint (T4.1's
// Circle Challenge collective-total requirement, see the schema migration's own comment).
const membershipHistoryInsertMock = vi.fn(
  (_row: unknown): Promise<{ error: { message: string } | null }> => Promise.resolve({ error: null })
);

// `.from("club").select(...).order(...)[.lt(...)].limit(...)` — GET (browse)'s list query.
const browseChain = {
  select: vi.fn(() => browseChain),
  order: vi.fn(() => browseChain),
  lt: vi.fn(() => browseChain),
  limit: vi.fn((): Promise<{ data: unknown[] | null; error: { message: string } | null }> => Promise.resolve({ data: [], error: null })),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: {
    from: (table: string) => {
      if (table === "club_member") return { select: membershipChain.select, insert: memberInsertMock };
      if (table === "club") return { insert: clubInsertMock, select: browseChain.select };
      if (table === "club_membership_history") return { insert: membershipHistoryInsertMock };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { GET, POST } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };

function postRequest(body: unknown) {
  return new Request("https://example.com/api/clubs", {
    method: "POST",
    headers: { authorization: "Bearer valid-jwt", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function getRequest(params?: Record<string, string>) {
  const url = new URL("https://example.com/api/clubs");
  for (const [key, value] of Object.entries(params ?? {})) url.searchParams.set(key, value);
  return new Request(url, { headers: { authorization: "Bearer valid-jwt" } });
}

describe("POST /api/clubs", () => {
  beforeEach(() => {
    vi.clearAllMocks();
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

  it("creates a club when the caller is NOT Premium — free for every tier, product-spec.md §4.24 AC1", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    clubInsertChain.single.mockResolvedValueOnce({
      data: {
        id: "club-free",
        name: "Lari Pagi",
        description: null,
        privacy: "public",
        invite_code: null,
        created_at: "2026-09-26T10:00:00Z",
      },
      error: null,
    });
    const res = await POST(postRequest({ name: "Lari Pagi" }));
    expect(res.status).toBe(201);
    expect(clubInsertMock).toHaveBeenCalled();
  });

  it("returns 409 when the caller is already in a club", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    membershipChain.maybeSingle.mockResolvedValueOnce({ data: { club_id: "club-existing" }, error: null });
    const res = await POST(postRequest({ name: "Lari Pagi" }));
    expect(res.status).toBe(409);
    expect(clubInsertMock).not.toHaveBeenCalled();
  });

  it("creates a public club with no invite_code when not already a member", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
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

    const insertedHistory = membershipHistoryInsertMock.mock.calls.at(-1)?.[0] as {
      club_id: string;
      user_id: string;
      joined_at: unknown;
      left_at: unknown;
    };
    expect(insertedHistory.club_id).toBe("club-1");
    expect(insertedHistory.user_id).toBe("usr-1");
    expect(insertedHistory.left_at).toBeUndefined();
  });

  it("generates an 8-character invite_code for an invite_only club", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
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

describe("GET /api/clubs (browse)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await GET(getRequest());
    expect(res.status).toBe(401);
  });

  it("returns an empty list with has_more false when there are no clubs", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    browseChain.limit.mockResolvedValueOnce({ data: [], error: null });
    const res = await GET(getRequest());
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({ clubs: [], has_more: false, next_before: null });
  });

  it("never returns invite_code, even for invite_only clubs", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    browseChain.limit.mockResolvedValueOnce({
      data: [
        {
          id: "club-1",
          name: "Elite Runners",
          description: "invite only",
          privacy: "invite_only",
          invite_code: "SECRET99",
          created_at: "2026-09-25T10:00:00Z",
        },
      ],
      error: null,
    });
    membershipChain.in.mockResolvedValueOnce({ data: [{ club_id: "club-1" }, { club_id: "club-1" }], error: null });

    const res = await GET(getRequest());
    const json = await res.json();
    expect(json.clubs[0]).toEqual({
      club_id: "club-1",
      name: "Elite Runners",
      description: "invite only",
      privacy: "invite_only",
      member_count: 2,
      created_at: "2026-09-25T10:00:00Z",
    });
    expect(JSON.stringify(json)).not.toContain("SECRET99");
  });
});
