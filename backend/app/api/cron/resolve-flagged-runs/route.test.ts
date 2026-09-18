import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const autoResolveOverdueLowConfidenceFlagsMock = vi.fn();

vi.mock("@/lib/anti-cheat/resolve-flagged-runs", () => ({
  autoResolveOverdueLowConfidenceFlags: (...args: unknown[]) => autoResolveOverdueLowConfidenceFlagsMock(...args),
}));

const { GET } = await import("./route");

function request(authHeader?: string) {
  return new Request("https://example.com/api/cron/resolve-flagged-runs", {
    headers: authHeader ? { authorization: authHeader } : {},
  });
}

describe("GET /api/cron/resolve-flagged-runs", () => {
  const originalSecret = process.env.CRON_SECRET;

  beforeEach(() => {
    process.env.CRON_SECRET = "test-cron-secret";
    autoResolveOverdueLowConfidenceFlagsMock.mockReset();
  });

  afterEach(() => {
    process.env.CRON_SECRET = originalSecret;
  });

  it("rejects a request with no Authorization header", async () => {
    const res = await GET(request());
    expect(res.status).toBe(401);
    expect(autoResolveOverdueLowConfidenceFlagsMock).not.toHaveBeenCalled();
  });

  it("rejects a request with the wrong secret", async () => {
    const res = await GET(request("Bearer wrong-secret"));
    expect(res.status).toBe(401);
    expect(autoResolveOverdueLowConfidenceFlagsMock).not.toHaveBeenCalled();
  });

  it("runs the auto-resolve logic and returns the resolved run ids when the secret matches", async () => {
    autoResolveOverdueLowConfidenceFlagsMock.mockResolvedValueOnce(["run-1", "run-2"]);
    const res = await GET(request("Bearer test-cron-secret"));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json).toEqual({ resolvedCount: 2, resolvedRunIds: ["run-1", "run-2"] });
  });
});
