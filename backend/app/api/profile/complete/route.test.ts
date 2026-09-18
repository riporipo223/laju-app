import { describe, expect, it, vi } from "vitest";

const requireAuthenticatedIdentityMock = vi.fn();
const upsertChain = {
  select: vi.fn(() => upsertChain),
  single: vi.fn(),
};
const upsertMock = vi.fn(() => upsertChain);

vi.mock("@/lib/auth", () => ({
  // Not importOriginal(): vitest's plain resolver can't follow the `@/` tsconfig alias from inside a
  // mock factory in this project's vitest.config.ts (no resolve.alias declared there). isAuthFailure's
  // real implementation is a one-liner, safe to duplicate here rather than fight module resolution for it.
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireAuthenticatedIdentity: (...args: unknown[]) => requireAuthenticatedIdentityMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: { from: () => ({ upsert: upsertMock }) },
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
  it("rejects when unauthenticated (identity check fails first)", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({
      response: Response.json({ error: "no" }, { status: 401 }),
    });
    const res = await POST(request({}));
    expect(res.status).toBe(401);
    expect(upsertMock).not.toHaveBeenCalled();
  });

  it("rejects with 400 if any region field is missing", async () => {
    requireAuthenticatedIdentityMock.mockResolvedValueOnce({ authUserId: "auth-1" });
    const res = await POST(
      request({
        username: "budi_run",
        region_kecamatan: "Cilandak",
        region_kabupaten_kota: "",
        region_provinsi: "DKI Jakarta",
      })
    );
    expect(res.status).toBe(400);
    expect(upsertMock).not.toHaveBeenCalled();
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
});
