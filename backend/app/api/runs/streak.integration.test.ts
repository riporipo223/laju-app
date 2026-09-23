/**
 * Regression for the server awarding no streak bonus: `POST /api/runs` passed `streakDays = 0`, so a run with a streak
 * was awarded less than the client's own estimate (found by the first real end-to-end run: estimate +2.7, awarded 1).
 * Now the server derives the streak from the user's run history. Real route + real Auth JWT + real database; prior runs
 * are seeded straight into `run` (a route can only score the run it is given).
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { localDayNumber, STREAK_UTC_OFFSET_MINUTES } from "@/lib/streak";
import { createTestAuthUser } from "@/test-support/auth";

const hasRealCredentials = Boolean(
  process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

const DAY = 86_400_000;

describe.skipIf(!hasRealCredentials)("POST /api/runs — server-side streak bonus", () => {
  let admin: import("@supabase/supabase-js").SupabaseClient;
  let POST: (request: Request) => Promise<Response>;
  const authIds: string[] = [];
  const userIds: string[] = [];

  // Anchor everything to the Asia/Jakarta day of "now" so the test cannot straddle a midnight.
  const today = localDayNumber(new Date());
  const dayStart = (offset: number) => (today + offset) * DAY - STREAK_UTC_OFFSET_MINUTES * 60_000;
  const noonOf = (offset: number) => dayStart(offset) + 12 * 3_600_000;

  async function makeUser(label: string) {
    const { createClient } = await import("@supabase/supabase-js");
    const anon = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const email = `streak-${label}-${Date.now()}@laju-test.local`;
    const session = await createTestAuthUser(admin, anon, email);
    authIds.push(session.authUserId);
    const { data, error } = await admin
      .from("user")
      .insert({
        auth_user_id: session.authUserId,
        email,
        username: `streak${label}${Date.now()}`,
      })
      .select("id")
      .single();
    if (error || !data) throw new Error(`user insert failed: ${error?.message}`);
    userIds.push(data.id);
    return { userId: data.id as string, jwt: session.accessToken };
  }

  async function seedRun(userId: string, dayOffsetFromToday: number, status = "validated", distanceMeters = 1000) {
    const { error } = await admin.from("run").insert({
      user_id: userId,
      status,
      anomaly_flags: [],
      gps_route: [],
      distance_meters: distanceMeters,
      duration_seconds: 360,
      started_at: new Date(noonOf(dayOffsetFromToday)).toISOString(),
    });
    if (error) throw new Error(`seed run failed: ${error.message}`);
  }

  /** ≈600 m at 3 m/s (pace ≈6:34/km → multiplier 1.0). Base points 0.6, so final = round(0.6 + 2 × streakDays). */
  function submit(jwt: string) {
    const startedAt = dayStart(0) + 3_600_000; // 01:00 WIB today — a distinct instant from every seeded run
    const route = Array.from({ length: 41 }, (_, i) => ({
      lat: -6.2615 + (i * 15) / 111_320,
      lng: 106.8106,
      timestamp: new Date(startedAt + i * 5000).toISOString(),
      elevation: 30,
    }));
    return POST(
      new Request("https://example.com/api/runs", {
        method: "POST",
        headers: { authorization: `Bearer ${jwt}`, "content-type": "application/json" },
        body: JSON.stringify({
          started_at: new Date(startedAt).toISOString(),
          ended_at: new Date(startedAt + 236_000).toISOString(),
          distance_meters: 600,
          duration_seconds: 236.8,
          gps_route: route,
        }),
      })
    );
  }

  const pointsFor = async (jwt: string) => {
    const response = await submit(jwt);
    expect(response.status).toBe(201);
    return (await response.json()).final_points_awarded as number;
  };

  beforeAll(async () => {
    const { createClient } = await import("@supabase/supabase-js");
    admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    ({ POST } = await import("./route"));
  }, 60000);

  afterAll(async () => {
    if (userIds.length) {
      await admin.from("point_transaction").delete().in("user_id", userIds);
      await admin.from("leaderboard_entry").delete().in("user_id", userIds);
      await admin.from("run").delete().in("user_id", userIds);
      await admin.from("user").delete().in("id", userIds);
    }
    for (const id of authIds) await admin.auth.admin.deleteUser(id);
  }, 60000);

  it("no history: today's run alone is a streak of 1 → the client estimate's number (0.6 + 2 → 3), no longer 1", async () => {
    const { jwt } = await makeUser("none");
    expect(await pointsFor(jwt)).toBe(3);
  }, 60000);

  it("two consecutive prior days: streak 3 → 0.6 + 6 → 7", async () => {
    const { userId, jwt } = await makeUser("two");
    await seedRun(userId, -1);
    await seedRun(userId, -2);
    expect(await pointsFor(jwt)).toBe(7);
  }, 60000);

  it("a gap resets it: runs 2 and 3 days ago but none yesterday → streak 1 → 3", async () => {
    const { userId, jwt } = await makeUser("gap");
    await seedRun(userId, -2);
    await seedRun(userId, -3);
    expect(await pointsFor(jwt)).toBe(3);
  }, 60000);

  it("a rejected run yesterday does not extend a streak (it must not be farmable)", async () => {
    const { userId, jwt } = await makeUser("rejected");
    await seedRun(userId, -1, "rejected");
    expect(await pointsFor(jwt)).toBe(3);
  }, 60000);

  it("a sub-100 m run yesterday does not count as a run day", async () => {
    const { userId, jwt } = await makeUser("tiny");
    await seedRun(userId, -1, "validated", 40);
    expect(await pointsFor(jwt)).toBe(3);
  }, 60000);

  it("the bonus is capped: ten prior days score the same as the cap allows (7 days → 0.6 + 14 → 15)", async () => {
    const { userId, jwt } = await makeUser("cap");
    for (let d = 1; d <= 10; d++) await seedRun(userId, -d);
    expect(await pointsFor(jwt)).toBe(15);
  }, 120000);
});
