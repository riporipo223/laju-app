/**
 * Regression for the first end-to-end run from the real app: the client measures elapsed time as a real number
 * (Core Data `Double`, e.g. 236.83 s) while `run.duration_seconds` is an integer column, and the route wrote the raw
 * value — every real run failed with a 500 and stayed queued forever. Every earlier test used whole seconds (or a
 * stubbed network), which is exactly how it stayed hidden. Real route + real Auth JWT + real database.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createTestAuthUser } from "@/test-support/auth";

const hasRealCredentials = Boolean(
  process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

describe.skipIf(!hasRealCredentials)("POST /api/runs — fractional duration", () => {
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
    const email = `duration-${Date.now()}@laju-test.local`;
    const session = await createTestAuthUser(admin, anon, email);
    authUserId = session.authUserId;
    jwt = session.accessToken;
    const { data, error } = await admin
      .from("user")
      .insert({
        auth_user_id: authUserId,
        email,
        username: `duration${Date.now()}`,
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
      await admin.from("point_transaction").delete().eq("user_id", userId);
      await admin.from("run").delete().eq("user_id", userId);
      await admin.from("user").delete().eq("id", userId);
    }
    if (authUserId) await admin.auth.admin.deleteUser(authUserId);
  }, 60000);

  /** ≈600 m at 3 m/s: one point every 5 s, 15 m apart — an ordinary, clean run. */
  function route(startedAt: number) {
    return Array.from({ length: 41 }, (_, i) => ({
      lat: -6.2615 + (i * 15) / 111_320,
      lng: 106.8106,
      timestamp: new Date(startedAt + i * 5000).toISOString(),
      elevation: 30,
    }));
  }

  const submit = (startedAt: number, durationSeconds: number) =>
    POST(
      new Request("https://example.com/api/runs", {
        method: "POST",
        headers: { authorization: `Bearer ${jwt}`, "content-type": "application/json" },
        body: JSON.stringify({
          started_at: new Date(startedAt).toISOString(),
          ended_at: new Date(startedAt + 200_000).toISOString(),
          distance_meters: 600,
          duration_seconds: durationSeconds,
          gps_route: route(startedAt),
        }),
      })
    );

  it("accepts the real client's fractional duration (236.83 s) and stores it rounded to an integer", async () => {
    const response = await submit(Date.parse("2026-09-21T06:00:00Z"), 236.83083403110504);
    expect(response.status).toBe(201);
    const { data } = await admin
      .from("run")
      .select("duration_seconds, avg_pace_sec_per_km")
      .eq("id", (await response.json()).run_id)
      .single();
    expect(data?.duration_seconds).toBe(237);
    expect(data?.avg_pace_sec_per_km).toBe(Math.round(237 / 0.6)); // pace uses the same rounded value
  }, 60000);

  it("still accepts a whole number of seconds", async () => {
    expect((await submit(Date.parse("2026-09-21T07:00:00Z"), 240)).status).toBe(201);
  }, 60000);

  it("refuses a duration that rounds to zero, instead of storing a 0-second run", async () => {
    const response = await submit(Date.parse("2026-09-21T08:00:00Z"), 0.4);
    expect(response.status).toBe(400);
    expect((await response.json()).error).toMatch(/at least 1 second/);
  }, 60000);
});
