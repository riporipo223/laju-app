/**
 * T2.20a / SEC-10 — the cost of one `POST /api/runs` is bounded BEFORE any anti-cheat work: an over-long route or an
 * oversized body is refused with 413, and nothing is written. Real route + real Auth JWT + real database.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createTestAuthUser } from "@/test-support/auth";

const hasRealCredentials = Boolean(
  process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

describe.skipIf(!hasRealCredentials)("POST /api/runs — payload caps (SEC-10)", () => {
  let admin: import("@supabase/supabase-js").SupabaseClient;
  let POST: (request: Request) => Promise<Response>;
  let authUserId = "";
  let userId = "";
  let jwt = "";

  beforeAll(async () => {
    const { createClient } = await import("@supabase/supabase-js");
    admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const anon = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const email = `t220a-cap-${Date.now()}@laju-test.local`;
    const session = await createTestAuthUser(admin, anon, email);
    authUserId = session.authUserId;
    jwt = session.accessToken;
    const { data, error } = await admin
      .from("user")
      .insert({
        auth_user_id: authUserId,
        email,
        username: `t220acap${Date.now()}`,
        region_kecamatan: "Kebayoran Baru",
        region_kabupaten_kota: "Jakarta Selatan",
        region_provinsi: "DKI Jakarta",
      })
      .select("id")
      .single();
    if (error || !data) throw new Error(`user insert failed: ${error?.message}`);
    userId = data.id;
    ({ POST } = await import("./route"));
  }, 60000);

  afterAll(async () => {
    if (userId) {
      await admin.from("run").delete().eq("user_id", userId);
      await admin.from("user").delete().eq("id", userId);
    }
    if (authUserId) await admin.auth.admin.deleteUser(authUserId);
  }, 60000);

  const submit = (body: string, extraHeaders: Record<string, string> = {}) =>
    POST(
      new Request("https://example.com/api/runs", {
        method: "POST",
        headers: { authorization: `Bearer ${jwt}`, "content-type": "application/json", ...extraHeaders },
        body,
      })
    );

  const point = (i: number) => ({ lat: -6.2 + i * 1e-6, lng: 106.8, timestamp: new Date(1_790_000_000_000 + i * 1000).toISOString(), elevation: 30 });
  const runOf = (points: number) =>
    JSON.stringify({
      started_at: "2026-09-21T06:00:00Z",
      ended_at: "2026-09-21T07:00:00Z",
      distance_meters: 5000,
      duration_seconds: 3600,
      gps_route: Array.from({ length: points }, (_, i) => point(i)),
    });

  const runCount = async () => (await admin.from("run").select("id", { count: "exact", head: true }).eq("user_id", userId)).count;

  it("refuses a route over 20,000 points with 413 and writes nothing", async () => {
    const before = await runCount();
    const response = await submit(runOf(20_001));
    expect(response.status).toBe(413);
    expect((await response.json()).error).toMatch(/at most 20000/);
    expect(await runCount()).toBe(before);
  }, 60000);

  it("refuses a declared body over the size cap with 413, before parsing it", async () => {
    const before = await runCount();
    const response = await submit("{}", { "content-length": "4000001" });
    expect(response.status).toBe(413);
    expect(await runCount()).toBe(before);
  }, 60000);

  it("still accepts a route exactly at the cap of points (the cap is inclusive) — reaches validation, not the size check", async () => {
    const response = await submit(runOf(20_000));
    expect(response.status).not.toBe(413);
  }, 120000);
});
