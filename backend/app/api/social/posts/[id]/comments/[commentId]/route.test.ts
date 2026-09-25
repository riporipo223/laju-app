import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();

// `.from("social_post_comment").delete().eq(...).eq(...).select(...).maybeSingle()` — the owner-scoped delete.
const deleteChain = {
  delete: vi.fn(() => deleteChain),
  eq: vi.fn(() => deleteChain),
  select: vi.fn(() => deleteChain),
  maybeSingle: vi.fn((): Promise<{ data: { id: string } | null; error: { message: string } | null }> => Promise.resolve({ data: null, error: null })),
};

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: {
    from: (table: string) => {
      if (table === "social_post_comment") return { delete: deleteChain.delete };
      throw new Error(`unexpected table: ${table}`);
    },
  },
}));

const { DELETE } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };
const params = () => Promise.resolve({ id: "post-1", commentId: "c1" });

function deleteRequest() {
  return new Request("https://example.com/api/social/posts/post-1/comments/c1", {
    method: "DELETE",
    headers: { authorization: "Bearer valid-jwt" },
  });
}

describe("DELETE /api/social/posts/[id]/comments/[commentId]", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(401);
    expect(deleteChain.delete).not.toHaveBeenCalled();
  });

  it("deletes the caller's own comment", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    deleteChain.maybeSingle.mockResolvedValueOnce({ data: { id: "c1" }, error: null });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({ comment_id: "c1", deleted: true });
    expect(deleteChain.eq).toHaveBeenCalledWith("id", "c1");
    expect(deleteChain.eq).toHaveBeenCalledWith("user_id", "usr-1");
  });

  it("returns 404 when the comment doesn't exist or isn't the caller's own — same response either way", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    deleteChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(404);
  });

  it("returns 500 when the delete query fails", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    deleteChain.maybeSingle.mockResolvedValueOnce({ data: null, error: { message: "db error" } });
    const res = await DELETE(deleteRequest(), { params: params() });
    expect(res.status).toBe(500);
  });
});
