import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();

// `.from("social_post").select("id").eq("id", id).maybeSingle()` — existence check before liking.
const postExistsChain = {
  select: vi.fn(() => postExistsChain),
  eq: vi.fn(() => postExistsChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: { id: string } | null; error: { message: string } | null }> =>
      Promise.resolve({ data: null, error: null })
  ),
};

// `.from("social_post_like").upsert(...)` — POST's like write.
const upsertMock = vi.fn(
  (_row: unknown, _opts: unknown): Promise<{ error: { message: string } | null }> => Promise.resolve({ error: null })
);

// `.from("social_post_like").delete().eq("post_id", id).eq("user_id", callerId)` — DELETE's unlike write.
let deleteLikeResult: { error: { message: string } | null } = { error: null };
const deleteLikeChain = {
  eq: vi.fn(() => deleteLikeChain),
  then: (resolve: (value: { error: { message: string } | null }) => void) => resolve(deleteLikeResult),
};
const deleteLikeMock = vi.fn(() => deleteLikeChain);

// `.from("social_post_like").select("*", {count, head:true}).eq("post_id", id)` — the shared like-count query.
const countChain = {
  select: vi.fn(() => countChain),
  eq: vi.fn(
    (): Promise<{ count: number | null; error: { message: string } | null }> =>
      Promise.resolve({ count: 0, error: null })
  ),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: {
    from: (table: string) => {
      if (table === "social_post") return { select: postExistsChain.select };
      if (table === "social_post_like") return { upsert: upsertMock, select: countChain.select, delete: deleteLikeMock };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { POST, DELETE } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };

function request(method: "POST" | "DELETE") {
  return new Request("https://example.com/api/social/posts/post-1/like", {
    method,
    headers: { authorization: "Bearer valid-jwt" },
  });
}

function context(id: string) {
  return { params: Promise.resolve({ id }) };
}

describe("POST /api/social/posts/[id]/like", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    deleteLikeResult = { error: null };
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await POST(request("POST"), context("post-1"));
    expect(res.status).toBe(401);
    expect(upsertMock).not.toHaveBeenCalled();
  });

  it("returns 404 when the post doesn't exist", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    postExistsChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await POST(request("POST"), context("post-missing"));
    expect(res.status).toBe(404);
    expect(upsertMock).not.toHaveBeenCalled();
  });

  it("upserts the like (idempotent, ignoreDuplicates) and returns the fresh count", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    postExistsChain.maybeSingle.mockResolvedValueOnce({ data: { id: "post-1" }, error: null });
    countChain.eq.mockResolvedValueOnce({ count: 3, error: null });

    const res = await POST(request("POST"), context("post-1"));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ post_id: "post-1", liked: true, like_count: 3 });
    expect(upsertMock).toHaveBeenCalledWith(
      { post_id: "post-1", user_id: "usr-1" },
      { onConflict: "post_id,user_id", ignoreDuplicates: true }
    );
  });

  it("returns 500 when the upsert itself fails", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    postExistsChain.maybeSingle.mockResolvedValueOnce({ data: { id: "post-1" }, error: null });
    upsertMock.mockResolvedValueOnce({ error: { message: "db down" } });
    const res = await POST(request("POST"), context("post-1"));
    expect(res.status).toBe(500);
  });
});

describe("DELETE /api/social/posts/[id]/like", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    deleteLikeResult = { error: null };
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await DELETE(request("DELETE"), context("post-1"));
    expect(res.status).toBe(401);
    expect(deleteLikeMock).not.toHaveBeenCalled();
  });

  it("scopes the delete to post_id and the caller's own user_id", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    countChain.eq.mockResolvedValueOnce({ count: 0, error: null });
    await DELETE(request("DELETE"), context("post-1"));
    expect(deleteLikeChain.eq).toHaveBeenCalledWith("post_id", "post-1");
    expect(deleteLikeChain.eq).toHaveBeenCalledWith("user_id", "usr-1");
  });

  it("is idempotent: unliking a never-liked post still returns 200 with the current count", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    countChain.eq.mockResolvedValueOnce({ count: 0, error: null });
    const res = await DELETE(request("DELETE"), context("post-1"));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ post_id: "post-1", liked: false, like_count: 0 });
  });

  it("returns 500 when the delete itself fails", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    deleteLikeResult = { error: { message: "db down" } };
    const res = await DELETE(request("DELETE"), context("post-1"));
    expect(res.status).toBe(500);
  });
});
