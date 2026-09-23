import { beforeEach, describe, expect, it, vi } from "vitest";

const requireAuthenticatedIdentityMock = vi.fn();
const upsertChain = {
  select: vi.fn(() => upsertChain),
  single: vi.fn(),
};
const upsertMock = vi.fn(() => upsertChain);
const existingUserMock = vi.fn();
const existingChain = { eq: vi.fn(() => existingChain), maybeSingle: () => existingUserMock() };

vi.mock("@/lib/auth", () => ({
  // Not importOriginal(): vitest's plain resolver can't follow the `@/` tsconfig alias from inside a
  // mock factory in this project's vitest.config.ts (no resolve.alias declared there). isAuthFailure's
  // real implementation is a one-liner, safe to duplicate here rather than fight module resolution for it.
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireAuthenticatedIdentity: (...args: unknown[]) => requireAuthenticatedIdentityMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: { from: () => ({ upsert: upsertMock, select: () => existingChain }) },
}));

const { POST } = await import("./route");

function request(body: unknown, header = "Bearer valid-jwt") {
  return new Request("https://example.com/api/profile/complete", {
    method: "POST",
    headers: { authorization: header, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/profile/complete", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    existingUserMock.mockResolvedValue({ data: null, error: null }); // default: no existing row
  });

  it("rejects when unauthenticated (identity check fails first)", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({
      response: Response.json({ error: "no" }, { status: 401 }),
    });
    const res = await POST(request({}));
    expect(res.status).toBe(401);
    expect(upsertMock).not.toHaveBeenCalled();
  });

  // Replaces "rejects with 400 if any region field is missing" (removed 2026-09-22): D1 was
  // reversed and region is no longer collected, so its absence must NOT be an error any more.
  it("accepts a profile with no region fields at all — region was removed (D1 reversed)", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    upsertChain.single.mockResolvedValueOnce({
      data: { id: "usr-1", username: "budi_run", total_points: 0, current_level: 1 },
      error: null,
    });
    const res = await POST(request({ username: "budi_run" }));
    expect(res.status).toBe(201);
    expect(upsertMock).toHaveBeenCalled();
  });

  // The columns still physically exist until Task B's migration, and an older app build may still
  // send them. They must be ignored, not rejected and not written — that tolerance is what keeps a
  // not-yet-updated client working through the rollout window.
  it("ignores region_* keys a stale client still sends, and does not persist them", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    upsertChain.single.mockResolvedValueOnce({
      data: { id: "usr-1", username: "budi_run", total_points: 0, current_level: 1 },
      error: null,
    });
    const res = await POST(
      request({
        username: "budi_run",
        region_kecamatan: "Cilandak",
        region_kabupaten_kota: "Jakarta Selatan",
        region_provinsi: "DKI Jakarta",
      })
    );
    expect(res.status).toBe(201);
    const persisted = upsertMock.mock.calls.at(0)?.at(0) as unknown as Record<string, unknown>;
    expect(persisted).not.toHaveProperty("region_kecamatan");
    expect(persisted).not.toHaveProperty("region_kabupaten_kota");
    expect(persisted).not.toHaveProperty("region_provinsi");
  });

  it("rejects with 400 if username is missing", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    const res = await POST(
      request({
        region_kecamatan: "Cilandak",
        region_kabupaten_kota: "Jakarta Selatan",
        region_provinsi: "DKI Jakarta",
      })
    );
    expect(res.status).toBe(400);
  });

  it("creates the profile and returns 201 matching database-api-spec.md §2.1's shape", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    upsertChain.single.mockResolvedValueOnce({
      data: { id: "usr_123", username: "budi_run", total_points: 0, current_level: 1 },
      error: null,
    });
    const res = await POST(
      request({
        username: "budi_run",
        display_name: "Budi",
        region_kecamatan: "Cilandak",
        region_kabupaten_kota: "Jakarta Selatan",
        region_provinsi: "DKI Jakarta",
      })
    );
    expect(res.status).toBe(201);
    const json = await res.json();
    expect(json).toEqual({ id: "usr_123", username: "budi_run", total_points: 0, current_level: 1 });
    expect(upsertMock).toHaveBeenCalledWith(
      expect.objectContaining({ auth_user_id: "auth-1", username: "budi_run" }),
      { onConflict: "auth_user_id" }
    );
  });

  const validBody = {
    username: "budi",
    region_kecamatan: "Kebayoran Baru",
    region_kabupaten_kota: "Jakarta Selatan",
    region_provinsi: "DKI Jakarta",
  };

  it("rejects a soft-deleted account with 401 and never writes (T2.22, B7-10: a still-valid JWT must not undo deletion)", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    existingUserMock.mockResolvedValueOnce({ data: { deleted_at: "2026-09-19T00:00:00Z" }, error: null });

    const res = await POST(request(validBody));

    expect(res.status).toBe(401);
    expect(upsertMock).not.toHaveBeenCalled();
  });

  it("still lets an existing, not-deleted account update its profile", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    existingUserMock.mockResolvedValueOnce({ data: { deleted_at: null }, error: null });
    upsertChain.single.mockResolvedValueOnce({
      data: { id: "u1", username: "budi", total_points: 0, current_level: 1 },
      error: null,
    });

    const res = await POST(request(validBody));

    expect(res.status).toBe(201);
    expect(upsertMock).toHaveBeenCalledTimes(1);
  });
});
