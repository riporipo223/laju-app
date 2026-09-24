import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();

// `.from("run").select(...).eq(...).maybeSingle()` — the ownership/status lookup before a post is created.
const runChain = {
  select: vi.fn(() => runChain),
  eq: vi.fn(() => runChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: { user_id: string; status: string } | null; error: { message: string } | null }> =>
      Promise.resolve({ data: null, error: null })
  ),
};

// `.from("social_post").insert(...).select(...).single()` — POST's insert.
const postInsertChain = {
  select: vi.fn(() => postInsertChain),
  single: vi.fn(
    (): Promise<{
      data: { id: string; run_id: string; caption: string | null; created_at: string } | null;
      error: { message: string } | null;
    }> => Promise.resolve({ data: null, error: null })
  ),
};
const postInsertMock = vi.fn((_row: unknown) => postInsertChain);

// `.from("social_post").select(...).order(...)[.lt(...)].limit(...)` — GET's feed query.
const feedChain = {
  select: vi.fn(() => feedChain),
  order: vi.fn(() => feedChain),
  lt: vi.fn(() => feedChain),
  limit: vi.fn((): Promise<{ data: unknown[] | null; error: { message: string } | null }> => Promise.resolve({ data: [], error: null })),
};

// `.from("social_post_like").select("post_id, user_id").in(...)` — GET's batched like lookup.
const likeSelectChain = {
  select: vi.fn(() => likeSelectChain),
  in: vi.fn(
    (): Promise<{ data: { post_id: string; user_id: string }[] | null; error: { message: string } | null }> =>
      Promise.resolve({ data: [], error: null })
  ),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: {
    from: (table: string) => {
      if (table === "run") return { select: runChain.select };
      if (table === "social_post") return { insert: postInsertMock, select: feedChain.select };
      if (table === "social_post_like") return { select: likeSelectChain.select };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { POST, GET } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };

function postRequest(body: unknown) {
  return new Request("https://example.com/api/social/posts", {
    method: "POST",
    headers: { authorization: "Bearer valid-jwt", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function getRequest(params?: Record<string, string>) {
  const url = new URL("https://example.com/api/social/posts");
  for (const [key, value] of Object.entries(params ?? {})) url.searchParams.set(key, value);
  return new Request(url, { headers: { authorization: "Bearer valid-jwt" } });
}

describe("POST /api/social/posts", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await POST(postRequest({ run_id: "run-1" }));
    expect(res.status).toBe(401);
    expect(postInsertMock).not.toHaveBeenCalled();
  });

  it("returns 400 when run_id is missing", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(postRequest({}));
    expect(res.status).toBe(400);
  });

  it("returns 400 when caption exceeds 280 characters", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(postRequest({ run_id: "run-1", caption: "x".repeat(281) }));
    expect(res.status).toBe(400);
  });

  it("returns 404 when the run does not exist", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    runChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await POST(postRequest({ run_id: "run-missing" }));
    expect(res.status).toBe(404);
  });

  it("returns 403 when the run belongs to a different user", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    runChain.maybeSingle.mockResolvedValueOnce({ data: { user_id: "usr-someone-else", status: "validated" }, error: null });
    const res = await POST(postRequest({ run_id: "run-1" }));
    expect(res.status).toBe(403);
    expect(postInsertMock).not.toHaveBeenCalled();
  });

  it.each(["flagged", "rejected"])("returns 422 when the run status is %s (not validated/approved)", async (status) => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    runChain.maybeSingle.mockResolvedValueOnce({ data: { user_id: "usr-1", status }, error: null });
    const res = await POST(postRequest({ run_id: "run-1" }));
    expect(res.status).toBe(422);
    expect(postInsertMock).not.toHaveBeenCalled();
  });

  it.each(["validated", "approved"])("creates a post for a %s run owned by the caller", async (status) => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    runChain.maybeSingle.mockResolvedValueOnce({ data: { user_id: "usr-1", status }, error: null });
    postInsertChain.single.mockResolvedValueOnce({
      data: { id: "post-1", run_id: "run-1", caption: "Nice run!", created_at: "2026-09-24T10:00:00Z" },
      error: null,
    });

    const res = await POST(postRequest({ run_id: "run-1", caption: "  Nice run!  " }));
    expect(res.status).toBe(201);
    const json = await res.json();
    expect(json).toEqual({ post_id: "post-1", run_id: "run-1", caption: "Nice run!", created_at: "2026-09-24T10:00:00Z" });

    const insertedRow = postInsertMock.mock.calls.at(-1)?.[0] as { user_id: string; run_id: string; caption: string | null };
    expect(insertedRow).toEqual({ user_id: "usr-1", run_id: "run-1", caption: "Nice run!" });
  });

  it("stores a null caption when none is given", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    runChain.maybeSingle.mockResolvedValueOnce({ data: { user_id: "usr-1", status: "validated" }, error: null });
    postInsertChain.single.mockResolvedValueOnce({
      data: { id: "post-2", run_id: "run-1", caption: null, created_at: "2026-09-24T10:00:00Z" },
      error: null,
    });
    await POST(postRequest({ run_id: "run-1" }));
    const insertedRow = postInsertMock.mock.calls.at(-1)?.[0] as { caption: string | null };
    expect(insertedRow.caption).toBeNull();
  });
});

describe("GET /api/social/posts", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await GET(getRequest());
    expect(res.status).toBe(401);
  });

  it("returns 400 for an unparseable before cursor", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await GET(getRequest({ before: "not-a-date" }));
    expect(res.status).toBe(400);
  });

  it.each(["0", "51", "abc"])("returns 400 for an out-of-range limit (%s)", async (limit) => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await GET(getRequest({ limit }));
    expect(res.status).toBe(400);
  });

  it("applies the before cursor as a lt filter and requests page size + 1", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    feedChain.limit.mockResolvedValueOnce({ data: [], error: null });
    await GET(getRequest({ before: "2026-09-20T00:00:00Z", limit: "10" }));
    expect(feedChain.lt).toHaveBeenCalledWith("created_at", "2026-09-20T00:00:00.000Z");
    expect(feedChain.limit).toHaveBeenCalledWith(11);
  });

  it("returns an empty feed with has_more false when there are no posts", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    feedChain.limit.mockResolvedValueOnce({ data: [], error: null });
    const res = await GET(getRequest());
    const json = await res.json();
    expect(json).toEqual({ posts: [], has_more: false, next_before: null });
  });

  it("maps author/run fields, like_count, and liked_by_caller from the batched like query", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    feedChain.limit.mockResolvedValueOnce({
      data: [
        {
          id: "post-1",
          user_id: "usr-2",
          run_id: "run-1",
          caption: "GG",
          created_at: "2026-09-24T10:00:00Z",
          author: { username: "budi_run", display_name: "Budi", avatar_url: null },
          run: { distance_meters: 5000, duration_seconds: 1800, avg_pace_sec_per_km: 360, final_points_awarded: 12 },
        },
      ],
      error: null,
    });
    likeSelectChain.in.mockResolvedValueOnce({
      data: [
        { post_id: "post-1", user_id: "usr-1" }, // the caller
        { post_id: "post-1", user_id: "usr-3" },
      ],
      error: null,
    });

    const res = await GET(getRequest());
    const json = await res.json();
    expect(json.has_more).toBe(false);
    expect(json.posts).toEqual([
      {
        post_id: "post-1",
        user_id: "usr-2",
        username: "budi_run",
        display_name: "Budi",
        avatar_url: null,
        run_id: "run-1",
        distance_meters: 5000,
        duration_seconds: 1800,
        avg_pace_sec_per_km: 360,
        final_points_awarded: 12,
        caption: "GG",
        created_at: "2026-09-24T10:00:00Z",
        like_count: 2,
        liked_by_caller: true,
      },
    ]);
  });

  it("has_more is true and next_before is the last returned row's created_at when page size + 1 rows come back", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const rows = Array.from({ length: 21 }, (_, i) => ({
      id: `post-${i}`,
      user_id: "usr-2",
      run_id: `run-${i}`,
      caption: null,
      created_at: `2026-09-24T10:00:${String(20 - i).padStart(2, "0")}Z`,
      author: null,
      run: null,
    }));
    feedChain.limit.mockResolvedValueOnce({ data: rows, error: null });
    likeSelectChain.in.mockResolvedValueOnce({ data: [], error: null });

    const res = await GET(getRequest());
    const json = await res.json();
    expect(json.has_more).toBe(true);
    expect(json.posts).toHaveLength(20);
    expect(json.posts[19].post_id).toBe("post-19");
    expect(json.next_before).toBe(json.posts[19].created_at);
  });
});
