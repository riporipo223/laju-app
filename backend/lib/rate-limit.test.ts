import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

const rpc = vi.fn();
vi.mock("./supabase", () => ({ supabaseAdmin: { rpc: (...args: unknown[]) => rpc(...args) } }));

import {
  clientIp,
  enforceIpLimit,
  enforceUserLimit,
  hit,
  IP_RATE_LIMIT,
  RATE_LIMIT_RULES,
  rateLimitedResponse,
} from "./rate-limit";

afterEach(() => rpc.mockReset());

describe("rate limiter — unit (database mocked)", () => {
  it("fails OPEN and logs when the database call errors — a limiter must never refuse a healthy request", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    rpc.mockResolvedValue({ data: null, error: { message: "connection refused" } });
    expect(await hit("user:x", { windowSeconds: 60, limit: 1 })).toEqual({ allowed: true, retryAfterSeconds: 0 });
    expect(log).toHaveBeenCalledOnce();
    log.mockRestore();
  });

  it("fails open when the call throws outright (network)", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    rpc.mockRejectedValue(new Error("fetch failed"));
    expect((await hit("user:x", { windowSeconds: 60, limit: 1 })).allowed).toBe(true);
    log.mockRestore();
  });

  it("puts the window length into the stored key so a minute bucket and an hour bucket can never merge", async () => {
    rpc.mockResolvedValue({ data: [{ allowed: true, retry_after_seconds: 1 }], error: null });
    await hit("user:abc:runs.post", { windowSeconds: 60, limit: 30 });
    await hit("user:abc:runs.post", { windowSeconds: 3600, limit: 300 });
    expect(rpc.mock.calls.map((call) => call[1].p_key)).toEqual(["user:abc:runs.post:60", "user:abc:runs.post:3600"]);
  });

  it("a refused minute window does not also burn the hour budget", async () => {
    rpc.mockResolvedValueOnce({ data: [{ allowed: false, retry_after_seconds: 12 }], error: null });
    const response = await enforceUserLimit("user-1", "runs.post");
    expect(response?.status).toBe(429);
    expect(rpc).toHaveBeenCalledTimes(1); // runs.post has two windows; the second was never reached
  });

  it("builds the documented 429: Retry-After header and {error, retry_after_seconds} body", async () => {
    const response = rateLimitedResponse(37);
    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("37");
    expect(await response.json()).toEqual({ error: "rate_limited", retry_after_seconds: 37 });
  });

  it("takes the client address from x-forwarded-for (first hop) and does not limit a request that has none", async () => {
    expect(clientIp(new Request("https://x", { headers: { "x-forwarded-for": "1.2.3.4, 10.0.0.1" } }))).toBe("1.2.3.4");
    expect(clientIp(new Request("https://x"))).toBeNull();
    expect(await enforceIpLimit(new Request("https://x"))).toBeNull();
    expect(rpc).not.toHaveBeenCalled();
    rpc.mockResolvedValue({ data: [{ allowed: true, retry_after_seconds: 1 }], error: null });
    await enforceIpLimit(new Request("https://x", { headers: { "x-forwarded-for": "1.2.3.4" } }));
    expect(rpc.mock.calls[0]![1]).toMatchObject({ p_key: `ip:1.2.3.4:${IP_RATE_LIMIT.windowSeconds}`, p_limit: IP_RATE_LIMIT.limit });
  });
});

/**
 * DoD item 1: "every endpoint is covered by the per-user layer (or documented as exempt), and every request is
 * covered by the per-IP layer". Checked structurally so a NEW route cannot silently ship without a rule.
 */
describe("rate limiter — every route is covered", () => {
  function routeFiles(dir: string): string[] {
    return readdirSync(dir).flatMap((entry) => {
      const path = join(dir, entry);
      if (statSync(path).isDirectory()) return routeFiles(path);
      return entry === "route.ts" ? [path] : [];
    });
  }
  const routes = routeFiles(join(__dirname, "../app/api"));
  /** Exempt with a stated reason: secret-gated, called by Vercel Cron only, no user and no public caller. */
  const EXEMPT = ["cron/resolve-flagged-runs/route.ts"];

  it("finds the expected set of routes (guards against the walk silently matching nothing)", () => {
    expect(routes.length).toBeGreaterThanOrEqual(8);
  });

  it.each(routes.map((path) => [path.split("app/api/")[1]!, path]))("%s", (name, path) => {
    const source = readFileSync(path, "utf8");
    if (EXEMPT.includes(name)) return;
    if (name === "health/route.ts") {
      expect(source, "health has no user: it must use the per-IP layer").toContain("enforceIpLimit(request)");
      return;
    }
    const uses = [...source.matchAll(/(?:requireUser|requireAuthenticatedIdentity)\(request, "([\w.]+)"\)/g)];
    expect(uses.length, `${name} must pass a rate-limit rule to its auth call`).toBeGreaterThan(0);
    for (const use of uses) expect(Object.keys(RATE_LIMIT_RULES)).toContain(use[1]);
  });
});
