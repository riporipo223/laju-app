import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();

// `.from("social_post").delete().eq("id", id).eq("user_id", callerId).select("id")` — DELETE's scoped delete.
const deleteChain = {
  eq: vi.fn(() => deleteChain),
  select: vi.fn(
    (): Promise<{ data: { id: string }[] | null; error: { message: string } | null }> =>
      Promise.resolve({ data: [], error: null })
  ),
};
const deleteMock = vi.fn(() => deleteChain);

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: { from: () => ({ delete: deleteMock }) },
}));

const { DELETE } = await import("./route");

const completeUser = { id: "usr-1", auth_user_id: "auth-1", deleted_at: null };

function deleteRequest() {
  return new Request("https://example.com/api/social/posts/post-1", {
    method: "DELETE",
    headers: { authorization: "Bearer valid-jwt" },
  });
}

function context(id: string) {
  return { params: Promise.resolve({ id }) };
}

describe("DELETE /api/social/posts/[id]", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await DELETE(deleteRequest(), context("post-1"));
    expect(res.status).toBe(401);
    expect(deleteMock).not.toHaveBeenCalled();
  });

  it("scopes the delete to the caller's own user_id, not just the post id", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    deleteChain.select.mockResolvedValueOnce({ data: [{ id: "post-1" }], error: null });
    await DELETE(deleteRequest(), context("post-1"));
    expect(deleteChain.eq).toHaveBeenCalledWith("id", "post-1");
    expect(deleteChain.eq).toHaveBeenCalledWith("user_id", "usr-1");
  });

  it("returns 404 (not 403) when the post doesn't exist or belongs to someone else — v1 delete-own-post moderation", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    deleteChain.select.mockResolvedValueOnce({ data: [], error: null });
    const res = await DELETE(deleteRequest(), context("post-not-owned"));
    expect(res.status).toBe(404);
  });

  it("returns 200 with deleted: true on a successful delete", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    deleteChain.select.mockResolvedValueOnce({ data: [{ id: "post-1" }], error: null });
    const res = await DELETE(deleteRequest(), context("post-1"));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ post_id: "post-1", deleted: true });
  });

  it("returns 500 when the delete itself errors", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    deleteChain.select.mockResolvedValueOnce({ data: null, error: { message: "db down" } });
    const res = await DELETE(deleteRequest(), context("post-1"));
    expect(res.status).toBe(500);
  });
});
