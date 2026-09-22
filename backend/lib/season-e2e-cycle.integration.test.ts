/**
 * T3.10 — phase DoD gate. Not new functionality: this is the one composite scenario that exercises the
 * whole season close→open cycle end to end with multiple seeded users in a single pass, so a boundary bug
 * between T3.6/T3.7/T3.7a/T3.8/T3.9 — each already covered by its own integration test in isolation — cannot
 * hide between them. Same real-Supabase, move-and-restore-the-real-season pattern as those tests; every row
 * created here is prefixed `T310`.
 *
 * Five DoD bullets, one scenario:
 *  1. Full close→open cycle with seeded multi-user data on the global leaderboard.
 *  2. Lifetime `user.total_points`/`current_level` unchanged post-transition.
 *  3. Season league (T3.7a) resets — computed from the new season's points only.
 *  4. Previous season's final rank still retrievable (T3.8) after the transition.
 *  5. `GET /api/seasons/active` (T3.9's data source) reflects the new season correctly.
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

describe.skipIf(!hasRealCredentials)("T3.10 — season close/open cycle, phase DoD gate", () => {
  let admin: import("@supabase/supabase-js").SupabaseClient;
  let anon: import("@supabase/supabase-js").SupabaseClient;
  let real: SeasonRow[] = [];
  let realEnd: number;
  const day = 86_400_000;
  const iso = (ms: number) => new Date(ms).toISOString();
  const userIds: string[] = [];
  const authIds: string[] = [];
  let counter = 0;

  async function newSeason(label: string, startMs: number, endMs: number) {
    const { data, error } = await admin
      .from("season")
      .insert({ name: `T310-${label}-${Date.now()}`, start_at: iso(startMs), end_at: iso(endMs), status: "upcoming" })
      .select("*")
      .single();
    if (error || !data) throw new Error(`season: ${error?.message}`);
    return data as SeasonRow;
  }

  async function makeUser(label: string, authUserId: string = crypto.randomUUID()) {
    counter += 1;
    const { data, error } = await admin
      .from("user")
      .insert({
        auth_user_id: authUserId,
        email: `t310-${label}-${Date.now()}-${counter}@laju-test.local`,
        username: `t310${label}${Date.now()}${counter}`,
        region_kecamatan: "x",
        region_kabupaten_kota: "y",
        region_provinsi: "z",
      })
      .select("id")
      .single();
    if (error || !data) throw new Error(`user: ${error?.message}`);
    userIds.push(data.id);
    return data.id as string;
  }

  /**
   * A run row plus its ledger row (what `POST /api/runs` leaves behind) — written through the real
   * `recordRunPointsAndUpdateAggregate`, which targets whichever season is currently `active` (never a
   * `seasonId` argument), so `user.total_points`/`current_level` end up genuinely non-zero before the
   * transition — what makes the "unchanged after the transition" assertion meaningful. Callers must
   * therefore only call this once the intended season has actually been made active.
   */
  async function addRun(userId: string, amount: number) {
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
    const { recordRunPointsAndUpdateAggregate } = await import("./point-transaction");
    await recordRunPointsAndUpdateAggregate(userId, data.id, amount);
  }

  const rebuild = () => admin.rpc("rebuild_global_leaderboard");
  const transition = (id: string, to: string) => admin.rpc("transition_season", { p_season: id, p_to: to });

  async function board(seasonId: string) {
    const { data } = await admin
      .from("leaderboard_entry")
      .select("user_id, points, rank")
      .eq("season_id", seasonId)
      .eq("scope_type", "global")
      .order("rank");
    return (data ?? []) as { user_id: string; points: number; rank: number }[];
  }

  async function lifetimeStats(userId: string) {
    const { data } = await admin.from("user").select("total_points, current_level").eq("id", userId).single();
    return data as { total_points: number; current_level: number };
  }

  async function league(userId: string, seasonId: string) {
    const { data, error } = await admin.rpc("season_points", { p_user: userId, p_season: seasonId });
    if (error || typeof data !== "number") throw new Error(`season_points: ${error?.message}`);
    const { leagueFor } = await import("./season-league");
    return leagueFor(data);
  }

  async function restore() {
    const { data: testSeasons } = await admin.from("season").select("id").like("name", "T310-%");
    const testSeasonIds = (testSeasons ?? []).map((row: { id: string }) => row.id);
    await admin.from("season").update({ status: "ended" }).like("name", "T310-%");
    for (const season of real) await admin.from("season").update({ status: season.status }).eq("id", season.id);
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
      await admin.from("point_transaction").delete().in("season_id", testSeasonIds);
      await admin.from("season").delete().in("id", testSeasonIds);
    }
    for (const id of authIds.splice(0)) await admin.auth.admin.deleteUser(id);
    await rebuild();
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

  it("close season A, open season B, seeded with 3 users: leaderboard, lifetime stats, league, history and the active endpoint all agree", async () => {
    const seasonA = await newSeason("A", realEnd, realEnd + 30 * day);
    const seasonB = await newSeason("B", realEnd + 30 * day, realEnd + 60 * day);

    // --- Season A: active, 3 users earn points, board settles ---
    expect((await transition(seasonA.id, "active")).error).toBeNull();
    const gold = await makeUser("gold"); // will finish A platinum, B nothing yet
    const mid = await makeUser("mid");
    const runner = await makeUser("runner");
    await addRun(gold, 700);
    await addRun(mid, 200);
    await addRun(runner, 50);
    await rebuild();
    expect((await board(seasonA.id)).map((row) => [row.user_id, row.rank, row.points])).toEqual([
      [gold, 1, 700],
      [mid, 2, 200],
      [runner, 3, 50],
    ]);

    const lifetimeBefore = {
      gold: await lifetimeStats(gold),
      mid: await lifetimeStats(mid),
      runner: await lifetimeStats(runner),
    };
    expect(lifetimeBefore.gold.total_points).toBe(700);

    // --- Close A, open B: DoD bullet 1 (the transition itself) ---
    expect((await transition(seasonB.id, "active")).error).toBeNull();

    // --- DoD bullet 2: lifetime stats untouched by the transition ---
    expect(await lifetimeStats(gold)).toEqual(lifetimeBefore.gold);
    expect(await lifetimeStats(mid)).toEqual(lifetimeBefore.mid);
    expect(await lifetimeStats(runner)).toEqual(lifetimeBefore.runner);

    // --- Season B starts empty, then a DIFFERENT ranking forms — proves it is not carried over ---
    expect(await board(seasonB.id)).toEqual([]);
    await addRun(runner, 900); // last in A, first in B
    await addRun(mid, 40);
    // gold (A's champion) earns nothing in B — must not appear in B's board at all
    await rebuild();
    expect((await board(seasonB.id)).map((row) => [row.user_id, row.rank, row.points])).toEqual([
      [runner, 1, 900],
      [mid, 2, 40],
    ]);

    // --- DoD bullet 3: season league (T3.7a) computed from B's points only, not A's ---
    expect(await league(gold, seasonA.id)).toBe("platinum"); // A's standing is unaffected by B existing
    expect(await league(gold, seasonB.id)).toBe("bronze"); // 0 points in B — A's platinum does not carry over
    expect(await league(runner, seasonB.id)).toBe("platinum"); // B's own top scorer, on B's points alone

    // --- DoD bullet 4: season A's final rank still retrievable after the transition (T3.8) ---
    const { data: frozenA } = await admin
      .from("season_result")
      .select("user_id, final_rank, final_points, league")
      .eq("season_id", seasonA.id)
      .order("final_rank");
    expect(frozenA).toEqual([
      { user_id: gold, final_rank: 1, final_points: 700, league: "platinum" },
      { user_id: mid, final_rank: 2, final_points: 200, league: "silver" },
      { user_id: runner, final_rank: 3, final_points: 50, league: "bronze" },
    ]);

    // Same fact through the actual client-facing route (GET /api/seasons/history), for a real Auth JWT.
    const email = `t310-history-${Date.now()}@laju-test.local`;
    const session = await createTestAuthUser(admin, anon, email);
    authIds.push(session.authUserId);
    await admin
      .from("user")
      .update({ auth_user_id: session.authUserId, email })
      .eq("id", mid);
    const { GET: getHistory } = await import("../app/api/seasons/history/route");
    const historyResponse = await getHistory(
      new Request("https://example.com/api/seasons/history", { headers: { authorization: `Bearer ${session.accessToken}` } })
    );
    expect(historyResponse.status).toBe(200);
    const historyBody = await historyResponse.json();
    expect(historyBody.seasons).toHaveLength(1);
    expect(historyBody.seasons[0]).toMatchObject({ season_id: seasonA.id, final_rank: 2, final_points: 200, league: "silver" });

    // --- DoD bullet 5: GET /api/seasons/active reflects the NEW season, T3.9's own data source ---
    const { GET: getActive } = await import("../app/api/seasons/active/route");
    const activeResponse = await getActive(
      new Request("https://example.com/api/seasons/active", { headers: { authorization: `Bearer ${session.accessToken}` } })
    );
    expect(activeResponse.status).toBe(200);
    const activeBody = await activeResponse.json();
    expect(activeBody.id).toBe(seasonB.id);
    expect(activeBody.me).toEqual({ season_points: 40, league: "bronze" }); // mid's B points, not A's 200
    expect(activeBody.days_remaining).toBe(Math.ceil((seasonB.end_at ? Date.parse(seasonB.end_at) - Date.now() : 0) / day));
  }, 180000);
});
