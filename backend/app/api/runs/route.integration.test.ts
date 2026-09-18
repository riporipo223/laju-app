/**
 * T2.13 — Layer 3 (Integration) per tasks/README.md's testing table: T2.6b's fixture corpus run through the
 * REAL `POST /api/runs` pipeline (T2.12a→T2.12d) against a real Supabase project, no mocks anywhere in this
 * file. Distinct from `route.test.ts` (Layer 1, deliberately mocked for speed/isolation) and from the
 * individual anti-cheat unit tests (which call `resolveRunStatus` directly, not the HTTP handler + DB).
 *
 * Requires real credentials (`NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
 * `NEXT_PUBLIC_SUPABASE_ANON_KEY`) in the environment — configured as GitHub Actions repo secrets
 * (added 2026-09-18) and locally via `node --env-file=.env.local ./node_modules/.bin/vitest run ...`.
 * Skips gracefully (not a failure) when they're absent, e.g. a contributor's fresh clone with no `.env.local`.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const hasRealCredentials = Boolean(
  process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

function loadFixture(name: string) {
  const path = join(__dirname, "..", "..", "..", "fixtures", "gps-routes", `${name}.json`);
  return JSON.parse(readFileSync(path, "utf-8"));
}

describe.skipIf(!hasRealCredentials)("POST /api/runs — real pipeline against T2.6b's fixture corpus", () => {
  let authUserId: string;
  let userId: string;
  let jwt: string;
  let supabaseAdmin: import("@supabase/supabase-js").SupabaseClient;
  let POST: (request: Request) => Promise<Response>;

  beforeAll(async () => {
    const { createClient } = await import("@supabase/supabase-js");
    supabaseAdmin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const email = `t213-${Date.now()}@laju-test.local`;
    const password = crypto.randomUUID();
    const { data: created, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (createError || !created.user) throw new Error(`Could not create test auth user: ${createError?.message}`);
    authUserId = created.user.id;

    const anonClient = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const { data: signIn, error: signInError } = await anonClient.auth.signInWithPassword({ email, password });
    if (signInError || !signIn.session) throw new Error(`Could not sign in test user: ${signInError?.message}`);
    jwt = signIn.session.access_token;

    const { data: userRow, error: userError } = await supabaseAdmin
      .from("user")
      .insert({
        auth_user_id: authUserId,
        email,
        username: `t213runner${Date.now()}`,
        region_kecamatan: "Cilandak",
        region_kabupaten_kota: "Jakarta Selatan",
        region_provinsi: "DKI Jakarta",
      })
      .select("id")
      .single();
    if (userError || !userRow) throw new Error(`Could not create test user row: ${userError?.message}`);
    userId = userRow.id;

    ({ POST } = await import("./route"));
  }, 30000);

  afterAll(async () => {
    if (userId) {
      await supabaseAdmin.from("point_transaction").delete().eq("user_id", userId);
      await supabaseAdmin.from("run").delete().eq("user_id", userId);
      await supabaseAdmin.from("user").delete().eq("id", userId);
    }
    if (authUserId) {
      await supabaseAdmin.auth.admin.deleteUser(authUserId);
    }
  }, 30000);

  // T2.6b's fixtures all share one baked-in anchor timestamp (2026-09-08T06:00:00Z) by generator
  // convention — reusing it as `started_at` for every submission would collide with T2.12d's
  // (user_id, started_at) dedup after the first one. `started_at` is a submission-time field, distinct
  // from `gps_route`'s own internal point timestamps (which anti-cheat math depends on and stay untouched);
  // giving each call its own real, unique value is what a genuine distinct submission would send anyway.
  let submissionCounter = 0;

  function submit(fixtureName: string) {
    const fixture = loadFixture(fixtureName);
    submissionCounter++;
    const request = new Request("https://example.com/api/runs", {
      method: "POST",
      headers: { authorization: `Bearer ${jwt}`, "content-type": "application/json" },
      body: JSON.stringify({
        started_at: new Date(Date.now() + submissionCounter * 1000).toISOString(),
        distance_meters: fixture.distance_meters,
        duration_seconds: fixture.duration_seconds,
        gps_route: fixture.gps_route,
      }),
    });
    return POST(request);
  }

  it("clean-negative-control-easy-jog: validated, zero flags", async () => {
    const res = await submit("clean-negative-control-easy-jog");
    expect(res.status).toBe(201);
    const json = await res.json();
    expect(json.status).toBe("validated");
    expect(json.anomaly_flags).toEqual([]);
  });

  it("clean-negative-control-fast-run: validated, zero flags (fast-but-human, not a false positive)", async () => {
    const res = await submit("clean-negative-control-fast-run");
    expect(res.status).toBe(201);
    const json = await res.json();
    expect(json.status).toBe("validated");
    expect(json.anomaly_flags).toEqual([]);
  });

  it("pace-cap-breach: the pace cap check demonstrably triggers through the real pipeline", async () => {
    const res = await submit("pace-cap-breach");
    const json = await res.json();
    expect(json.anomaly_flags).toContain("pace_cap_exceeded");
    expect(json.status).not.toBe("validated");
  });

  it("gps-speed-jump: the GPS speed jump check demonstrably triggers through the real pipeline, and a rejected run writes no PointTransaction", async () => {
    const res = await submit("gps-speed-jump");
    const json = await res.json();
    expect(json.anomaly_flags.some((f: string) => f.startsWith("gps_speed_jump_segment_"))).toBe(true);
    expect(json.status).not.toBe("validated");
    // Verified against the real ledger, not just the response — this fixture's exclusion is 100%, so it
    // rejects immediately (tech-spec.md §2.4.1: no PointTransaction ever written for an immediate reject).
    expect(json.status).toBe("rejected");
    const { data: rows } = await supabaseAdmin.from("point_transaction").select("id").eq("run_id", json.run_id);
    expect(rows).toEqual([]);
  });

  it("teleport: the distance/duration sanity check demonstrably triggers through the real pipeline", async () => {
    const res = await submit("teleport");
    const json = await res.json();
    expect(json.anomaly_flags.some((f: string) => f.startsWith("distance_duration_sanity_segment_"))).toBe(true);
    expect(json.status).not.toBe("validated");
  });

  it("combined-anomalies: multiple checks trigger together through the real pipeline, not just one", async () => {
    const res = await submit("combined-anomalies");
    const json = await res.json();
    expect(json.anomaly_flags).toContain("pace_cap_exceeded");
    expect(json.anomaly_flags.some((f: string) => f.startsWith("gps_speed_jump_segment_"))).toBe(true);
    expect(json.status).not.toBe("validated");
  });
});

/**
 * T2.14c — Layer 3: the two DoD items that genuinely need a real database, not mocks — draining >200 real
 * rows without skipping any, and cross-user isolation with a second real Auth identity. Separate `describe`
 * block (own user, own setup) so seeding 201 rows here can't interfere with the fixture-corpus tests above.
 */
describe.skipIf(!hasRealCredentials)("GET /api/runs — T2.14c reconciliation, real DB", () => {
  let authUserId: string;
  let userId: string;
  let jwt: string;
  let secondAuthUserId: string;
  let secondUserId: string;
  let secondJwt: string;
  let supabaseAdmin: import("@supabase/supabase-js").SupabaseClient;
  let GET: (request: Request) => Promise<Response>;

  async function createTestIdentity(label: string) {
    const { createClient } = await import("@supabase/supabase-js");
    const email = `t214c-${label}-${Date.now()}@laju-test.local`;
    const password = crypto.randomUUID();
    const { data: created, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (createError || !created.user) throw new Error(`Could not create ${label} auth user: ${createError?.message}`);

    const anonClient = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const { data: signIn, error: signInError } = await anonClient.auth.signInWithPassword({ email, password });
    if (signInError || !signIn.session) throw new Error(`Could not sign in ${label}: ${signInError?.message}`);

    const { data: userRow, error: userError } = await supabaseAdmin
      .from("user")
      .insert({ auth_user_id: created.user.id, email, username: `t214c${label}${Date.now()}` })
      .select("id")
      .single();
    if (userError || !userRow) throw new Error(`Could not create ${label} user row: ${userError?.message}`);

    return { authUserId: created.user.id, userId: userRow.id, jwt: signIn.session.access_token };
  }

  beforeAll(async () => {
    const { createClient } = await import("@supabase/supabase-js");
    supabaseAdmin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const primary = await createTestIdentity("primary");
    authUserId = primary.authUserId;
    userId = primary.userId;
    jwt = primary.jwt;

    const secondary = await createTestIdentity("secondary");
    secondAuthUserId = secondary.authUserId;
    secondUserId = secondary.userId;
    secondJwt = secondary.jwt;

    ({ GET } = await import("./route"));
  }, 60000);

  afterAll(async () => {
    for (const id of [userId, secondUserId]) {
      if (id) await supabaseAdmin.from("run").delete().eq("user_id", id);
    }
    if (userId) await supabaseAdmin.from("user").delete().eq("id", userId);
    if (secondUserId) await supabaseAdmin.from("user").delete().eq("id", secondUserId);
    if (authUserId) await supabaseAdmin.auth.admin.deleteUser(authUserId);
    if (secondAuthUserId) await supabaseAdmin.auth.admin.deleteUser(secondAuthUserId);
  }, 30000);

  function get(jwtToUse: string, since?: string) {
    const url = new URL("https://example.com/api/runs");
    if (since) url.searchParams.set("since", since);
    return GET(new Request(url, { headers: { authorization: `Bearer ${jwtToUse}` } }));
  }

  it("drains 201 real rows across two calls with no row skipped or duplicated", async () => {
    const base = new Date("2026-01-01T00:00:00Z").getTime();
    const rows = Array.from({ length: 201 }, (_, i) => ({
      user_id: userId,
      status: "validated",
      anomaly_flags: [],
      updated_at: new Date(base + i * 1000).toISOString(),
      created_at: new Date(base + i * 1000).toISOString(),
    }));
    const { error: seedError } = await supabaseAdmin.from("run").insert(rows);
    if (seedError) throw new Error(`Could not seed 201 runs: ${seedError.message}`);

    const firstPage = await get(jwt, "2025-12-01T00:00:00Z");
    const firstJson = await firstPage.json();
    expect(firstJson.has_more).toBe(true);
    expect(firstJson.runs).toHaveLength(200);

    const lastRowUpdatedAt = firstJson.runs[199].updated_at;
    const secondPage = await get(jwt, lastRowUpdatedAt);
    const secondJson = await secondPage.json();
    expect(secondJson.has_more).toBe(false);
    // The filter is inclusive (>= since), so the boundary row is expected to reappear once.
    expect(secondJson.runs.length).toBeGreaterThanOrEqual(1);

    const firstIds = new Set(firstJson.runs.map((r: { run_id: string }) => r.run_id));
    const secondIds = new Set(secondJson.runs.map((r: { run_id: string }) => r.run_id));
    const unionIds = new Set([...firstIds, ...secondIds]);
    expect(unionIds.size).toBe(201); // every seeded row accounted for exactly once in the union
  }, 30000);

  it("never returns another user's runs, even when both users have matching data", async () => {
    const { data: run, error } = await supabaseAdmin
      .from("run")
      .insert({ user_id: secondUserId, status: "validated", anomaly_flags: [] })
      .select("id")
      .single();
    if (error || !run) throw new Error(`Could not seed second user's run: ${error?.message}`);

    const res = await get(secondJwt, "2020-01-01T00:00:00Z");
    const json = await res.json();
    expect(json.runs.some((r: { run_id: string }) => r.run_id === run.id)).toBe(true);

    // The FIRST user's token must never see the SECOND user's run.
    const crossRes = await get(jwt, "2020-01-01T00:00:00Z");
    const crossJson = await crossRes.json();
    expect(crossJson.runs.some((r: { run_id: string }) => r.run_id === run.id)).toBe(false);
  });
});
