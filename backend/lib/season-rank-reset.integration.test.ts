/**
 * T3.7 — season-scoped rank reset against the real Supabase project. Like season-lifecycle.integration.test.ts these tests move the
 * real active season (that is what they test) and restore it exactly afterwards; every row they create is prefixed `T37`.
 *
 * The DoD they prove: after a transition rank starts fresh — a user who topped the old season is NOT top of the new one just
 * because of carried-over lifetime points — while `user.total_points`/`current_level` are untouched; plus the two timing gaps the
 * migration closed (final standings of the ended season, and a board that exists from the first second of the new one).
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

describe.skipIf(!hasRealCredentials)("season rank reset — real database", () => {
  let admin: import("@supabase/supabase-js").SupabaseClient;
  let real: SeasonRow[] = [];
  let realEnd: number;
  const day = 86_400_000;
  const iso = (ms: number) => new Date(ms).toISOString();
  const userIds: string[] = [];
  const authIds: string[] = [];
  let runCounter = 0;

  async function newSeason(label: string, startMs: number, endMs: number) {
    const { data, error } = await admin
      .from("season")
      .insert({ name: `T37-${label}-${Date.now()}`, start_at: iso(startMs), end_at: iso(endMs), status: "upcoming" })
      .select("*")
      .single();
    if (error || !data) throw new Error(`season: ${error?.message}`);
    return data as SeasonRow;
  }

  async function makeUser(label: string) {
    const { data, error } = await admin
      .from("user")
      .insert({
        auth_user_id: crypto.randomUUID(),
        email: `t37-${label}-${Date.now()}-${runCounter++}@laju-test.local`,
        username: `t37${label}${Date.now()}${runCounter}`,
        display_name: `T37 ${label}`,
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

  /** A run row with no ledger row yet — the real writer (`recordRunPointsAndUpdateAggregate`) adds that. */
  async function addRunRowOnly(userId: string, status = "validated", amount = 0) {
    const { data, error } = await admin
      .from("run")
      .insert({
        user_id: userId,
        status,
        anomaly_flags: [],
        gps_route: [],
        distance_meters: 1000,
        duration_seconds: 360,
        started_at: iso(Date.now() - 10 * day + runCounter++ * 1000),
        final_points_awarded: amount,
      })
      .select("id")
      .single();
    if (error || !data) throw new Error(`run: ${error?.message}`);
    return data.id as string;
  }

  /** A run row plus its ledger row in `seasonId` (what `POST /api/runs` leaves behind). */
  async function addRun(userId: string, seasonId: string, amount: number, status = "validated") {
    const runId = await addRunRowOnly(userId, status, amount);
    const { error } = await admin
      .from("point_transaction")
      .insert({ user_id: userId, run_id: runId, season_id: seasonId, amount, type: "run" });
    if (error) throw new Error(`tx: ${error.message}`);
    return runId;
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

  async function restore() {
    const { data: testSeasons } = await admin.from("season").select("id").like("name", "T37-%");
    const testSeasonIds = (testSeasons ?? []).map((row: { id: string }) => row.id);
    await admin.from("season").update({ status: "ended" }).like("name", "T37-%");
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
    const { data } = await admin.from("season").select("*").not("name", "like", "T37-%").not("name", "like", "T36-%");
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

  it("rank starts fresh: the old season's champion is absent from the new season, and lifetime points/level are untouched", async () => {
    const seasonA = await newSeason("A", realEnd, realEnd + 30 * day);
    const seasonB = await newSeason("B", realEnd + 30 * day, realEnd + 60 * day);
    expect((await transition(seasonA.id, "active")).error).toBeNull();

    const big = await makeUser("big");
    const small = await makeUser("small");
    await addRun(big, seasonA.id, 500);
    await addRun(small, seasonA.id, 100);
    const { recomputeUserPointsAggregate } = await import("./point-transaction");
    const before = await recomputeUserPointsAggregate(big);
    await rebuild();
    expect((await board(seasonA.id)).map((row) => [row.user_id, row.rank])).toEqual([
      [big, 1],
      [small, 2],
    ]);

    expect((await transition(seasonB.id, "active")).error).toBeNull();

    // the new season has no rows for the champion — nothing is carried over
    expect(await board(seasonB.id)).toEqual([]);
    // …and the transition did not touch lifetime numbers
    const { data: after } = await admin.from("user").select("total_points, current_level").eq("id", big).single();
    expect(after).toEqual({ total_points: before.totalPoints, current_level: before.currentLevel });
    expect(before.totalPoints).toBe(500);

    // A run in the NEW season, scored by the real ledger writer: the small user (lifetime 160) leads a champion with lifetime 500.
    const runId = await addRunRowOnly(small, "validated", 60);
    const { recordRunPointsAndUpdateAggregate } = await import("./point-transaction");
    const smallAfter = await recordRunPointsAndUpdateAggregate(small, runId, 60);
    expect(smallAfter.totalPoints).toBe(160); // 100 (season A) + 60 (season B): lifetime spans seasons
    await rebuild();
    expect((await board(seasonB.id)).map((row) => [row.user_id, row.points, row.rank])).toEqual([[small, 60, 1]]);

    // the old season's standings are immutable history — the new season's rebuild did not touch them
    expect((await board(seasonA.id)).map((row) => [row.user_id, row.points])).toEqual([
      [big, 500],
      [small, 100],
    ]);
  }, 120000);

  it("the ended season's FINAL standings include points earned after the last 15-minute rebuild", async () => {
    const seasonA = await newSeason("fA", realEnd, realEnd + 30 * day);
    const seasonB = await newSeason("fB", realEnd + 30 * day, realEnd + 60 * day);
    await transition(seasonA.id, "active");
    const runner = await makeUser("late");
    await addRun(runner, seasonA.id, 100);
    await rebuild(); // what the cron job last wrote
    await addRun(runner, seasonA.id, 50); // earned after it — would be missing from the final board without the closing rebuild

    await transition(seasonB.id, "active");
    expect((await board(seasonA.id)).map((row) => row.points)).toEqual([150]);
  }, 120000);

  it("the new season's board exists from the first second (scope row present), instead of waiting for the next cron run", async () => {
    const seasonA = await newSeason("sA", realEnd, realEnd + 30 * day);
    const seasonB = await newSeason("sB", realEnd + 30 * day, realEnd + 60 * day);
    await transition(seasonA.id, "active");
    await transition(seasonB.id, "active");
    const { data: scope } = await admin
      .from("leaderboard_scope")
      .select("computed_at, user_count")
      .eq("season_id", seasonB.id)
      .eq("scope_type", "global")
      .maybeSingle();
    expect(scope?.computed_at).toBeTruthy();
    expect(scope?.user_count).toBe(0);
  }, 120000);

  it("a flagged run that resolves AFTER the season changed is compensated in the season it was earned in", async () => {
    const seasonA = await newSeason("rA", realEnd, realEnd + 30 * day);
    const seasonB = await newSeason("rB", realEnd + 30 * day, realEnd + 60 * day);
    await transition(seasonA.id, "active");
    const runner = await makeUser("flagged");
    const flaggedRun = await addRun(runner, seasonA.id, 40, "flagged");
    await admin.from("run").update({ flag_confidence: "low" }).eq("id", flaggedRun);
    await transition(seasonB.id, "active");

    const { resolveFlaggedRun } = await import("./anti-cheat/resolve-flagged-runs");
    await resolveFlaggedRun(flaggedRun, "rejected", "manual");

    const { data: ledger } = await admin.from("point_transaction").select("amount, type, season_id").eq("user_id", runner);
    const bySeason = (id: string) => (ledger ?? []).filter((row: { season_id: string }) => row.season_id === id);
    expect(bySeason(seasonA.id).map((row: { amount: number }) => row.amount).sort((a, b) => a - b)).toEqual([-40, 40]);
    expect(bySeason(seasonB.id)).toEqual([]); // the new season is not charged for the old one's run
  }, 120000);

  it("GET /api/leaderboard right after a transition: the new season, an empty board, and the caller unranked — not an error", async () => {
    const seasonA = await newSeason("gA", realEnd, realEnd + 30 * day);
    const seasonB = await newSeason("gB", realEnd + 30 * day, realEnd + 60 * day);
    await transition(seasonA.id, "active");
    const { createClient } = await import("@supabase/supabase-js");
    const anon = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const email = `t37-route-${Date.now()}@laju-test.local`;
    const session = await createTestAuthUser(admin, anon, email);
    authIds.push(session.authUserId);
    const { data: profile } = await admin
      .from("user")
      .insert({
        auth_user_id: session.authUserId,
        email,
        username: `t37route${Date.now()}`,
        region_kecamatan: "x",
        region_kabupaten_kota: "y",
        region_provinsi: "z",
      })
      .select("id")
      .single();
    userIds.push(profile!.id);
    await addRun(profile!.id, seasonA.id, 30); // ranked in the old season
    await transition(seasonB.id, "active");

    const { GET } = await import("../app/api/leaderboard/route");
    const response = await GET(
      new Request("https://example.com/api/leaderboard?scope=global", {
        headers: { authorization: `Bearer ${session.accessToken}` },
      })
    );
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.season_id).toBe(seasonB.id);
    expect(body.entries).toEqual([]);
    expect(body.me).toBeNull();
    expect(body.computed_at).toBeTruthy();
  }, 120000);
});
