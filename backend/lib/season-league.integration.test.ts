/**
 * T3.7a — Season League against the real Supabase project: `season_points()` must equal `leaderboard_entry.points`, and
 * `GET /api/seasons/active` must return the caller's `me` for a real Auth JWT. The reset test moves the real active season and
 * restores it exactly; every row created here is deleted afterwards (seasons are prefixed `T37A`).
 */
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { createTestAuthUser } from "@/test-support/auth";

const hasRealCredentials = Boolean(
  process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

interface SeasonRow {
  id: string;
  name: string;
  status: string;
  end_at: string;
}

describe.skipIf(!hasRealCredentials)("season league — real database", () => {
  let admin: import("@supabase/supabase-js").SupabaseClient;
  let anon: import("@supabase/supabase-js").SupabaseClient;
  let real: SeasonRow[] = [];
  let activeId: string;
  let realEnd: number;
  const day = 86_400_000;
  const iso = (ms: number) => new Date(ms).toISOString();
  const userIds: string[] = [];
  const authIds: string[] = [];
  let counter = 0;

  async function makeUser(label: string, authUserId: string = crypto.randomUUID()) {
    counter += 1;
    const { data, error } = await admin
      .from("user")
      .insert({
        auth_user_id: authUserId,
        email: `t37a-${label}-${Date.now()}-${counter}@laju-test.local`,
        username: `t37a${label}${Date.now()}${counter}`,
      })
      .select("id")
      .single();
    if (error || !data) throw new Error(`user: ${error?.message}`);
    userIds.push(data.id);
    return data.id as string;
  }

  async function addRun(userId: string, seasonId: string, amount: number, status: string, type = "run") {
    counter += 1;
    const { data, error } = await admin
      .from("run")
      .insert({
        user_id: userId,
        status,
        anomaly_flags: [],
        gps_route: [],
        distance_meters: 1000,
        duration_seconds: 360,
        started_at: iso(Date.now() - 10 * day + counter * 1000),
        final_points_awarded: amount,
      })
      .select("id")
      .single();
    if (error || !data) throw new Error(`run: ${error?.message}`);
    const { error: txError } = await admin
      .from("point_transaction")
      .insert({ user_id: userId, run_id: data.id, season_id: seasonId, amount, type });
    if (txError) throw new Error(`tx: ${txError.message}`);
    return data.id as string;
  }

  const seasonPoints = async (userId: string, seasonId: string) =>
    (await admin.rpc("season_points", { p_user: userId, p_season: seasonId })).data as number;

  async function restore() {
    const { data: testSeasons } = await admin.from("season").select("id").like("name", "T37A-%");
    const testSeasonIds = (testSeasons ?? []).map((row: { id: string }) => row.id);
    await admin.from("season").update({ status: "ended" }).like("name", "T37A-%");
    for (const season of real) await admin.from("season").update({ status: season.status }).eq("id", season.id);
    if (testSeasonIds.length) await admin.from("season_result").delete().in("season_id", testSeasonIds); // T3.8
    if (userIds.length) {
      await admin.from("season_result").delete().in("user_id", userIds);
      await admin.from("point_transaction").delete().in("user_id", userIds);
      await admin.from("leaderboard_entry").delete().in("user_id", userIds);
      await admin.from("run").delete().in("user_id", userIds);
      await admin.from("user").delete().in("id", userIds);
      userIds.length = 0;
    }
    if (testSeasonIds.length) {
      await admin.from("leaderboard_entry").delete().in("season_id", testSeasonIds);
      await admin.from("leaderboard_scope").delete().in("season_id", testSeasonIds);
      await admin.from("season").delete().in("id", testSeasonIds);
    }
    for (const id of authIds.splice(0)) await admin.auth.admin.deleteUser(id);
    await admin.rpc("rebuild_global_leaderboard");
  }

  async function callSeasonsActive(accessToken?: string) {
    const { GET } = await import("../app/api/seasons/active/route");
    return GET(
      new Request("https://example.com/api/seasons/active", {
        headers: accessToken ? { authorization: `Bearer ${accessToken}` } : {},
      })
    );
  }

  beforeAll(async () => {
    const { createClient } = await import("@supabase/supabase-js");
    admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    anon = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const { data } = await admin.from("season").select("*").not("name", "like", "T3%");
    real = (data ?? []) as SeasonRow[];
    const active = real.filter((season) => season.status === "active");
    if (active.length !== 1) throw new Error(`expected exactly one real active season, found ${active.length}`);
    activeId = active[0]!.id;
    realEnd = Date.parse(active[0]!.end_at);
  }, 60000);

  afterEach(async () => {
    await restore();
  }, 60000);

  afterAll(async () => {
    await restore();
  }, 60000);

  it("season_points equals leaderboard_entry.points: flagged excluded until resolved, a rejected run nets to nothing", async () => {
    const userId = await makeUser("eq");
    await addRun(userId, activeId, 100, "validated");
    await addRun(userId, activeId, 20, "approved");
    await addRun(userId, activeId, 40, "flagged"); // held: not counted yet
    const rejected = await addRun(userId, activeId, 30, "rejected");
    // compensating row of a rejected run carries the run's id (excluded together with the original)
    await admin.from("point_transaction").insert({ user_id: userId, run_id: rejected, season_id: activeId, amount: -30, type: "adjustment" });

    expect(await seasonPoints(userId, activeId)).toBe(120);
    await admin.rpc("rebuild_global_leaderboard");
    const { data: entry } = await admin
      .from("leaderboard_entry")
      .select("points")
      .eq("season_id", activeId)
      .eq("scope_type", "global")
      .eq("user_id", userId)
      .single();
    expect(entry?.points).toBe(120);
    expect(await seasonPoints(userId, activeId)).toBe(entry?.points);
  }, 60000);

  it("GET /api/seasons/active returns me.season_points / me.league for a real JWT; 401 without one", async () => {
    const email = `t37a-route-${Date.now()}@laju-test.local`;
    const session = await createTestAuthUser(admin, anon, email);
    authIds.push(session.authUserId);
    const userId = await makeUser("route", session.authUserId);
    await addRun(userId, activeId, 300, "validated");

    const res = await callSeasonsActive(session.accessToken);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.id).toBe(activeId);
    expect(body.me).toEqual({ season_points: 300, league: "gold" });

    expect((await callSeasonsActive()).status).toBe(401);
  }, 60000);

  it("me is null for a signed-in caller with no profile yet, and the season still returns", async () => {
    const session = await createTestAuthUser(admin, anon, `t37a-noprofile-${Date.now()}@laju-test.local`);
    authIds.push(session.authUserId);
    const res = await callSeasonsActive(session.accessToken);
    expect(res.status).toBe(200);
    expect((await res.json()).me).toBeNull();
  }, 60000);

  it("after a season transition the league comes from the new season only: Platinum last season, Bronze at 0", async () => {
    const insert = async (label: string, from: number, to: number) => {
      const { data, error } = await admin
        .from("season")
        .insert({ name: `T37A-${label}-${Date.now()}`, start_at: iso(from), end_at: iso(to), status: "upcoming" })
        .select("id")
        .single();
      if (error || !data) throw new Error(`season: ${error?.message}`);
      return data.id as string;
    };
    const seasonA = await insert("A", realEnd, realEnd + 30 * day);
    const seasonB = await insert("B", realEnd + 30 * day, realEnd + 60 * day);
    expect((await admin.rpc("transition_season", { p_season: seasonA, p_to: "active" })).error).toBeNull();

    const email = `t37a-reset-${Date.now()}@laju-test.local`;
    const session = await createTestAuthUser(admin, anon, email);
    authIds.push(session.authUserId);
    const userId = await makeUser("reset", session.authUserId);
    await addRun(userId, seasonA, 700, "validated");
    expect((await (await callSeasonsActive(session.accessToken)).json()).me).toEqual({ season_points: 700, league: "platinum" });

    expect((await admin.rpc("transition_season", { p_season: seasonB, p_to: "active" })).error).toBeNull();
    const body = await (await callSeasonsActive(session.accessToken)).json();
    expect(body.id).toBe(seasonB);
    expect(body.me).toEqual({ season_points: 0, league: "bronze" });
    expect(await seasonPoints(userId, seasonA)).toBe(700); // history untouched
  }, 120000);

  it("season_points is not callable with the public anon key", async () => {
    const { error } = await anon.rpc("season_points", { p_user: crypto.randomUUID(), p_season: activeId });
    expect(error).not.toBeNull();
  }, 30000);
});
