import { describe, expect, it, vi } from "vitest";

const getUserMock = vi.fn();
const maybeSingleMock = vi.fn();

vi.mock("./supabase", () => ({
  supabaseAdmin: {
    auth: { getUser: (...args: unknown[]) => getUserMock(...args) },
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: (...args: unknown[]) => maybeSingleMock(...args),
        }),
      }),
    }),
  },
}));

const { requireUser, isAuthFailure } = await import("./auth");

function requestWith(header: string | null) {
  const headers = new Headers();
  if (header !== null) headers.set("authorization", header);
  return new Request("https://example.com/api/auth/me", { headers });
}

describe("requireUser", () => {
  it("rejects a request with no Authorization header (401)", async () => {
    const result = await requireUser(requestWith(null));
    expect(isAuthFailure(result)).toBe(true);
    if (isAuthFailure(result)) expect(result.response.status).toBe(401);
  });

  it("rejects a malformed Authorization header (401)", async () => {
    const result = await requireUser(requestWith("Basic abc123"));
    expect(isAuthFailure(result)).toBe(true);
    if (isAuthFailure(result)) expect(result.response.status).toBe(401);
  });

  it("rejects an invalid/expired JWT (401)", async () => {
    getUserMock.mockResolvedValueOnce({ data: { user: null }, error: { message: "invalid" } });
    const result = await requireUser(requestWith("Bearer not-a-real-jwt"));
    expect(isAuthFailure(result)).toBe(true);
    if (isAuthFailure(result)) expect(result.response.status).toBe(401);
    expect(getUserMock).toHaveBeenCalledWith("not-a-real-jwt");
  });

  it("rejects a valid JWT with no matching user row (401)", async () => {
    getUserMock.mockResolvedValueOnce({ data: { user: { id: "auth-1" } }, error: null });
    maybeSingleMock.mockResolvedValueOnce({ data: null, error: null });
    const result = await requireUser(requestWith("Bearer valid-jwt"));
    expect(isAuthFailure(result)).toBe(true);
    if (isAuthFailure(result)) expect(result.response.status).toBe(401);
  });

  it("rejects a valid JWT for a soft-deleted account (401) — the specific T2.3 DoD claim", async () => {
    getUserMock.mockResolvedValueOnce({ data: { user: { id: "auth-1" } }, error: null });
    maybeSingleMock.mockResolvedValueOnce({
      data: { id: "user-1", auth_user_id: "auth-1", deleted_at: "2026-09-01T00:00:00Z" },
      error: null,
    });
    const result = await requireUser(requestWith("Bearer valid-jwt"));
    expect(isAuthFailure(result)).toBe(true);
    if (isAuthFailure(result)) expect(result.response.status).toBe(401);
  });

  it("accepts a valid JWT for a non-deleted account", async () => {
    getUserMock.mockResolvedValueOnce({ data: { user: { id: "auth-1" } }, error: null });
    maybeSingleMock.mockResolvedValueOnce({
      data: { id: "user-1", auth_user_id: "auth-1", deleted_at: null },
      error: null,
    });
    const result = await requireUser(requestWith("Bearer valid-jwt"));
    expect(isAuthFailure(result)).toBe(false);
    if (!isAuthFailure(result)) expect(result.user.id).toBe("user-1");
  });
});
