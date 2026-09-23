/**
 * T3.8 — final season results against the real Supabase project. The tests move the real active season and restore it exactly;
 * every row created here is deleted afterwards (seasons are prefixed `T38`).
 */
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { LEAGUE_BANDS } from "@/lib/season-league";
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

describe.skipIf(!hasRealCredentials)("season results — real database", () => {
  let admin: import("@supabase/supabase-js").SupabaseClient;
  let anon: import("@supabase/supabase-js").SupabaseClient;
  let real: SeasonRow[] = [];
  let realEnd: number;
  const day = 86_400_000;
  const iso = (ms: number) => new Date(ms).toISOString();
  const userIds: string[] = [];
  const authIds: string[] = [];
  let counter = 0;

  async function newSeason(label: string, from: number, to: number) {
    const { data, error } = await admin
      .from("season")
      .insert({ name: `T38-${label}-${Date.now()}`, start_at: iso(from), end_at: iso(to), status: "upcoming" })
      .select("id")
      .single();
    if (error || !data) throw new Error(`season: ${error?.message}`);
    return data.id as string;
  }

  async function makeUser(label: string, authUserId: string = crypto.randomUUID()) {
    counter += 1;
    const { data, error } = await admin
      .from("user")
      .insert({
        auth_user_id: authUserId,
        email: `t38-${label}-${Date.now()}-${counter}@laju-test.local`,
        username: `t38${label}${Date.now()}${counter}`,
      })
      .select("id")
      .single();
    if (error || !data) throw new Error(`user: ${error?.message}`);
    userIds.push(data.id);
    return data.id as string;
  }

  async function addRun(userId: string, seasonId: string, amount: number) {
    counter += 1;
    const { data, error } = await admin
      .from("run")
      .insert({
        user_id: userId,
        status: "validated",
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
      .insert({ user_id: userId, run_id: data.id, season_id: seasonId, amount, type: "run" });
    if (txError) throw new Error(`tx: ${txError.message}`);
  }

  const activate = (id: string) => admin.rpc("transition_season", { p_season: id, p_to: "active" });
  const rebuild = () => admin.rpc("rebuild_global_leaderboard");

  async function results(seasonId: string) {
    const { data } = await admin
      .from("season_result")
      .select("user_id, final_rank, final_points, league, participants")
      .eq("season_id", seasonId)
      .order("final_rank");
    return (data ?? []) as { user_id: string; final_rank: number; final_points: number; league: string; participants: number }[];
  }

  async function restore() {
    const { data: testSeasons } = await admin.from("season").select("id").like("name", "T38-%");
    const testSeasonIds = (testSeasons ?? []).map((row: { id: string }) => row.id);
    await admin.from("season").update({ status: "ended" }).like("name", "T38-%");
    for (const season of real) await admin.from("season").update({ status: season.status }).eq("id", season.id);
    // undo any band edit a failed test left behind
    for (const band of LEAGUE_BANDS) await admin.from("league_band").update({ min_points: band.minPoints }).eq("league", band.league);
    if (testSeasonIds.length) await admin.from("season_result").delete().in("season_id", testSeasonIds);
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
    await rebuild();
  }

  async function callHistory(accessToken?: string) {
    const { GET } = await import("../app/api/seasons/history/route");
    return GET(
      new Request("https://example.com/api/seasons/history", {
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
    realEnd = Date.parse(active[0]!.end_at);
  }, 60000);

  afterEach(async () => {
    await restore();
  }, 60000);

  afterAll(async () => {
    await restore();
  }, 60000);

  it("the league_band table and LEAGUE_BANDS in code are identical (the freeze runs in SQL, live me.league in TS)", async () => {
    const { data } = await admin.from("league_band").select("league, min_points").order("min_points");
    expect(data).toEqual(LEAGUE_BANDS.map((band) => ({ league: band.league, min_points: band.minPoints })));
  }, 30000);

  it("ending a season freezes every ranked user's final rank, points and league — including points added after the last rebuild", async () => {
    const seasonA = await newSeason("A", realEnd, realEnd + 30 * day);
    const seasonB = await newSeason("B", realEnd + 30 * day, realEnd + 60 * day);
    await activate(seasonA);
    const big = await makeUser("big");
    const mid = await makeUser("mid");
    const small = await makeUser("small");
    await addRun(big, seasonA, 700);
    await addRun(mid, seasonA, 100);
    await addRun(small, seasonA, 10);
    await rebuild();
    await addRun(small, seasonA, 5); // after the last rebuild: only the closing rebuild can include it

    expect(await results(seasonA)).toEqual([]); // nothing frozen while the season is running
    expect((await activate(seasonB)).error).toBeNull();

    expect(await results(seasonA)).toEqual([
      { user_id: big, final_rank: 1, final_points: 700, league: "platinum", participants: 3 },
      { user_id: mid, final_rank: 2, final_points: 100, league: "silver", participants: 3 },
      { user_id: small, final_rank: 3, final_points: 15, league: "bronze", participants: 3 },
    ]);
  }, 120000);

  it("results are not overwritten or lost: later rebuilds, later transitions and a second freeze all leave them as they were", async () => {
    const seasonA = await newSeason("iA", realEnd, realEnd + 30 * day);
    const seasonB = await newSeason("iB", realEnd + 30 * day, realEnd + 60 * day);
    const seasonC = await newSeason("iC", realEnd + 60 * day, realEnd + 90 * day);
    await activate(seasonA);
    const runner = await makeUser("imm");
    await addRun(runner, seasonA, 300);
    await activate(seasonB);
    const frozen = await results(seasonA);
    expect(frozen).toHaveLength(1);

    await addRun(runner, seasonB, 900);
    await rebuild();
    await activate(seasonC);
    expect(await results(seasonA)).toEqual(frozen);

    // even if the source rows change afterwards, freezing again is a no-op
    await admin.from("leaderboard_entry").update({ points: 1, rank: 9 }).eq("season_id", seasonA).eq("user_id", runner);
    const again = await admin.rpc("freeze_season_results", { p_season: seasonA });
    expect(again.data).toBe(0);
    expect(await results(seasonA)).toEqual(frozen);
  }, 120000);

  it("a later recalibration of the bands does not rewrite the league a past season ended in", async () => {
    const seasonA = await newSeason("cA", realEnd, realEnd + 30 * day);
    const seasonB = await newSeason("cB", realEnd + 30 * day, realEnd + 60 * day);
    await activate(seasonA);
    const runner = await makeUser("cal");
    await addRun(runner, seasonA, 700);
    await activate(seasonB);
    expect((await results(seasonA))[0]?.league).toBe("platinum");

    await admin.from("league_band").update({ min_points: 5000 }).eq("league", "platinum");
    expect((await results(seasonA))[0]?.league).toBe("platinum"); // stored, not derived
  }, 120000);

  it("advance_seasons (the hourly job) freezes the season it ends too", async () => {
    const seasonA = await newSeason("dA", realEnd, realEnd + 30 * day);
    const seasonB = await newSeason("dB", realEnd + 30 * day, realEnd + 60 * day);
    await activate(seasonA);
    const runner = await makeUser("adv");
    await addRun(runner, seasonA, 260);
    const { error } = await admin.rpc("advance_seasons", { p_now: iso(realEnd + 31 * day) });
    expect(error).toBeNull();
    expect((await results(seasonA)).map((row) => [row.final_rank, row.final_points, row.league])).toEqual([[1, 260, "gold"]]);
    expect((await admin.from("season").select("status").eq("id", seasonB).single()).data?.status).toBe("active");
  }, 120000);

  it("GET /api/seasons/history returns the caller's finished seasons for a real JWT; empty for a user with none; 401 without one", async () => {
    const seasonA = await newSeason("hA", realEnd, realEnd + 30 * day);
    const seasonB = await newSeason("hB", realEnd + 30 * day, realEnd + 60 * day);
    await activate(seasonA);
    const session = await createTestAuthUser(admin, anon, `t38-hist-${Date.now()}@laju-test.local`);
    authIds.push(session.authUserId);
    const userId = await makeUser("hist", session.authUserId);
    await addRun(userId, seasonA, 300);
    const other = await createTestAuthUser(admin, anon, `t38-none-${Date.now()}@laju-test.local`);
    authIds.push(other.authUserId);
    await makeUser("none", other.authUserId);
    await activate(seasonB);

    const res = await callHistory(session.accessToken);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.seasons).toHaveLength(1);
    expect(body.seasons[0]).toMatchObject({
      season_id: seasonA,
      final_rank: 1,
      final_points: 300,
      league: "gold",
      participants: 1,
    });
    expect(body.seasons[0].name).toMatch(/^T38-hA-/);

    expect((await (await callHistory(other.accessToken)).json()).seasons).toEqual([]);
    expect((await callHistory()).status).toBe(401);
  }, 120000);

  it("the public anon key can read neither season_result nor league_band, and cannot call freeze_season_results", async () => {
    const results = await anon.from("season_result").select("*").limit(1);
    expect(results.data ?? []).toEqual([]);
    const bands = await anon.from("league_band").select("*").limit(1);
    expect(bands.data ?? []).toEqual([]);
    const { error } = await anon.rpc("freeze_season_results", { p_season: crypto.randomUUID() });
    expect(error).not.toBeNull();
  }, 30000);
});
