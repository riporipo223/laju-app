import { beforeEach, describe, expect, it, vi } from "vitest";

const requireAuthenticatedIdentityMock = vi.fn();
const deleteAccountMock = vi.fn();

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireAuthenticatedIdentity: (...args: unknown[]) => requireAuthenticatedIdentityMock(...args),
}));

vi.mock("@/lib/account-deletion", () => ({
  deleteAccount: (...args: unknown[]) => deleteAccountMock(...args),
}));

const { DELETE } = await import("./route");

const request = () =>
  new Request("https://example.com/api/account", { method: "DELETE", headers: { authorization: "Bearer jwt" } });

describe("DELETE /api/account", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects an unauthenticated caller without deleting anything", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    expect((await DELETE(request())).status).toBe(401);
    expect(deleteAccountMock).not.toHaveBeenCalled();
  });

  it("deletes only the caller's own identity and matches the spec's response", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    deleteAccountMock.mockResolvedValueOnce({ hadProfile: true, flaggedRunsRejected: 0 });

    const res = await DELETE(request());

    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ deleted: true });
    expect(deleteAccountMock).toHaveBeenCalledWith("auth-1");
  });

  it("500s, without claiming success, when deletion fails partway (caller can retry)", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    deleteAccountMock.mockRejectedValueOnce(new Error("boom"));
    expect((await DELETE(request())).status).toBe(500);
  });
});
