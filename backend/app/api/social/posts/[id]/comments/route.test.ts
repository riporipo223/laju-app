import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();

// `.from("social_post").select(...).eq(...).maybeSingle()` — the post-existence lookup before a comment insert.
const postChain = {
  select: vi.fn(() => postChain),
  eq: vi.fn(() => postChain),
  maybeSingle: vi.fn((): Promise<{ data: { id: string } | null; error: { message: string } | null }> => Promise.resolve({ data: null, error: null })),
};

// `.from("social_post_comment").select(...).eq(...).order(...).limit(...)` — GET's list query.
const listChain = {
  select: vi.fn(() => listChain),
  eq: vi.fn(() => listChain),
  order: vi.fn(() => listChain),
  limit: vi.fn((): Promise<{ data: unknown[] | null; error: { message: string } | null }> => Promise.resolve({ data: [], error: null })),
};

// `.from("social_post_comment").insert(...).select(...).single()` — POST's insert.
const insertChain = {
  select: vi.fn(() => insertChain),
  single: vi.fn(
    (): Promise<{
      data: { id: string; post_id: string; user_id: string; content: string; created_at: string } | null;
      error: { message: string } | null;
    }> => Promise.resolve({ data: null, error: null })
  ),
};
const insertMock = vi.fn((_row: unknown) => insertChain);

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: {
    from: (table: string) => {
      if (table === "social_post") return { select: postChain.select };
      if (table === "social_post_comment") return { select: listChain.select, insert: insertMock };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { GET, POST } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };
const params = () => Promise.resolve({ id: "post-1" });

function postRequest(body: unknown) {
  return new Request("https://example.com/api/social/posts/post-1/comments", {
    method: "POST",
    headers: { authorization: "Bearer valid-jwt", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function getRequest() {
  return new Request("https://example.com/api/social/posts/post-1/comments", { headers: { authorization: "Bearer valid-jwt" } });
}

describe("GET /api/social/posts/[id]/comments", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await GET(getRequest(), { params: params() });
    expect(res.status).toBe(401);
  });

  it("returns the post's comments oldest-first", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    listChain.limit.mockResolvedValueOnce({
      data: [
        {
          id: "c1",
          post_id: "post-1",
          user_id: "usr-2",
          content: "Nice run!",
          created_at: "2026-09-25T10:00:00Z",
          author: { username: "budi_run", display_name: "Budi", avatar_url: null },
        },
      ],
      error: null,
    });
    const res = await GET(getRequest(), { params: params() });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({
      comments: [
        {
          comment_id: "c1",
          post_id: "post-1",
          user_id: "usr-2",
          username: "budi_run",
          display_name: "Budi",
          avatar_url: null,
          content: "Nice run!",
          created_at: "2026-09-25T10:00:00Z",
        },
      ],
    });
    expect(listChain.order).toHaveBeenCalledWith("created_at", { ascending: true });
  });

  it("returns 500 when the query fails", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    listChain.limit.mockResolvedValueOnce({ data: null, error: { message: "db error" } });
    const res = await GET(getRequest(), { params: params() });
    expect(res.status).toBe(500);
  });
});

describe("POST /api/social/posts/[id]/comments", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await POST(postRequest({ content: "Nice!" }), { params: params() });
    expect(res.status).toBe(401);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("returns 400 when content is missing", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(postRequest({}), { params: params() });
    expect(res.status).toBe(400);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("returns 400 when content exceeds 280 characters", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(postRequest({ content: "x".repeat(281) }), { params: params() });
    expect(res.status).toBe(400);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("returns 404 when the post does not exist", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    postChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await POST(postRequest({ content: "Nice!" }), { params: params() });
    expect(res.status).toBe(404);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("creates a comment for an existing post", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    postChain.maybeSingle.mockResolvedValueOnce({ data: { id: "post-1" }, error: null });
    insertChain.single.mockResolvedValueOnce({
      data: { id: "c1", post_id: "post-1", user_id: "usr-1", content: "Nice!", created_at: "2026-09-25T10:00:00Z" },
      error: null,
    });
    const res = await POST(postRequest({ content: "  Nice!  " }), { params: params() });
    expect(res.status).toBe(201);
    const json = await res.json();
    expect(json).toEqual({ comment_id: "c1", post_id: "post-1", user_id: "usr-1", content: "Nice!", created_at: "2026-09-25T10:00:00Z" });

    const insertedRow = insertMock.mock.calls.at(-1)?.[0] as { post_id: string; user_id: string; content: string };
    expect(insertedRow).toEqual({ post_id: "post-1", user_id: "usr-1", content: "Nice!" });
  });

  it("returns 500 when the insert fails", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    postChain.maybeSingle.mockResolvedValueOnce({ data: { id: "post-1" }, error: null });
    insertChain.single.mockResolvedValueOnce({ data: null, error: { message: "db error" } });
    const res = await POST(postRequest({ content: "Nice!" }), { params: params() });
    expect(res.status).toBe(500);
  });
});
