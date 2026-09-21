/**
 * T2.20a — Layer 3: the limiter against the real Supabase project. The properties that matter can only be shown
 * against a real database: atomicity under a concurrent burst (the failure mode of a read-then-write limiter),
 * that a window really resets, isolation between keys, and that the per-IP layer runs before the Auth call.
 * Skips without credentials.
 */
import { afterAll, describe, expect, it } from "vitest";

const hasRealCredentials = Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
const tag = `t220a-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

describe.skipIf(!hasRealCredentials)("rate limiter — real database", () => {
  afterAll(async () => {
    const { supabaseAdmin } = await import("./supabase");
    await supabaseAdmin.from("rate_limit_bucket").delete().like("key", `%${tag}%`);
  }, 30000);

  it("is atomic under concurrency: 40 simultaneous calls against a limit of 10 let exactly 10 through", async () => {
    const { hit } = await import("./rate-limit");
    const results = await Promise.all(
      Array.from({ length: 40 }, () => hit(`user:${tag}-atomic`, { windowSeconds: 3600, limit: 10 }))
    );
    expect(results.filter((result) => result.allowed)).toHaveLength(10);
    expect(results.filter((result) => !result.allowed)).toHaveLength(30);
  }, 60000);

  it("refuses over the limit with a Retry-After inside the window, then lets requests through again after it resets", async () => {
    const { hit } = await import("./rate-limit");
    // A window long enough that a slow CI round-trip (≈0.5 s here, more on a bad day) cannot straddle its end.
    const window = { windowSeconds: 6, limit: 3 };
    // Start just after a boundary so the whole burst lands in one window. Concurrent, so its length is one round-trip.
    const msIntoWindow = Date.now() % 6000;
    if (msIntoWindow > 500) await new Promise((resolve) => setTimeout(resolve, 6000 - msIntoWindow + 100));

    const burst = await Promise.all(Array.from({ length: 5 }, () => hit(`user:${tag}-reset`, window)));
    expect(burst.filter((result) => result.allowed)).toHaveLength(3);
    const refused = burst.filter((result) => !result.allowed);
    expect(refused).toHaveLength(2);
    for (const result of refused) {
      expect(result.retryAfterSeconds).toBeGreaterThanOrEqual(1);
      expect(result.retryAfterSeconds).toBeLessThanOrEqual(6);
    }

    await new Promise((resolve) => setTimeout(resolve, 6200));
    expect((await hit(`user:${tag}-reset`, window)).allowed).toBe(true);
  }, 60000);

  it("isolates keys: one user, one IP, or one route exhausting a limit does not limit another", async () => {
    const { hit } = await import("./rate-limit");
    const window = { windowSeconds: 3600, limit: 2 };
    for (let i = 0; i < 3; i++) await hit(`user:${tag}-a`, window);
    expect((await hit(`user:${tag}-a`, window)).allowed).toBe(false);
    expect((await hit(`user:${tag}-b`, window)).allowed).toBe(true); // another user
    expect((await hit(`ip:${tag}-1.1.1.1`, window)).allowed).toBe(true); // an IP
    expect((await hit(`user:${tag}-a:other-route`, window)).allowed).toBe(true); // same user, another route
  }, 60000);

  it("enforceUserLimit answers the documented 429 once a route's rule is exhausted (account.delete = 3/h)", async () => {
    const { enforceUserLimit } = await import("./rate-limit");
    const subject = `${tag}-acct`;
    for (let i = 0; i < 3; i++) expect(await enforceUserLimit(subject, "account.delete")).toBeNull();
    const refused = await enforceUserLimit(subject, "account.delete");
    expect(refused?.status).toBe(429);
    expect(Number(refused?.headers.get("Retry-After"))).toBeGreaterThanOrEqual(1);
    const body = await refused!.json();
    expect(body.error).toBe("rate_limited");
    expect(body.retry_after_seconds).toBeGreaterThanOrEqual(1);
  }, 60000);

  it("the per-IP layer runs BEFORE the Auth call: 401 until the ceiling, then 429 without ever reaching auth", async () => {
    const { requireAuthenticatedIdentity } = await import("./auth");
    const { IP_RATE_LIMIT } = await import("./rate-limit");
    // The real ceiling (120/min) is proven against production in T2.20a's live check; here a small one keeps this test
    // to a second or two, so a slow CI runner cannot let the window roll over mid-test.
    const original = { ...IP_RATE_LIMIT };
    Object.assign(IP_RATE_LIMIT, { windowSeconds: 30, limit: 5 });
    try {
      const msIntoWindow = Date.now() % 30000;
      if (msIntoWindow > 15000) await new Promise((resolve) => setTimeout(resolve, 30000 - msIntoWindow + 100));
      const ip = `203.0.113.7-${tag}`;
      const statuses: number[] = [];
      for (let i = 0; i < 8; i++) {
        const result = await requireAuthenticatedIdentity(
          new Request("https://example.com/api/x", { headers: { "x-forwarded-for": ip } }),
          "auth.me"
        );
        statuses.push("response" in result ? result.response.status : 200);
      }
      // No Authorization header: while under the ceiling the Auth path answers 401; past it, 429 comes first.
      expect(statuses).toEqual([401, 401, 401, 401, 401, 429, 429, 429]);
    } finally {
      Object.assign(IP_RATE_LIMIT, original);
    }
  }, 120000);

  it("reports the limiter's own overhead: one database call per counted hit", async () => {
    const { hit } = await import("./rate-limit");
    const samples: number[] = [];
    for (let i = 0; i < 15; i++) {
      const started = performance.now();
      await hit(`user:${tag}-latency`, { windowSeconds: 60, limit: 1000 });
      samples.push(performance.now() - started);
    }
    samples.sort((a, b) => a - b);
    console.log(`rate_limit_hit round-trip from this machine: median ${samples[7]!.toFixed(0)} ms, max ${samples[14]!.toFixed(0)} ms`);
    expect(samples[7]!).toBeLessThan(2000);
  }, 60000);
});
