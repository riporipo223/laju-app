/**
 * T2.18 — Layer 3: `rebuild_global_leaderboard()` (the pg_cron job) against the real Supabase project.
 * The rebuild lives in SQL (one atomic transaction), so there is nothing to mock — these tests call the real
 * function through `supabaseAdmin.rpc` and read the real tables. Skips without credentials, like the other
 * integration files.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const hasRealCredentials = Boolean(
  process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

/**
 * CI's runner occasionally drops the very first request to Supabase (`TypeError: fetch failed`, before any
 * response) — a transport blip, not a logic failure. Retry only that specific error, a few times; any real
 * database/logic error still surfaces immediately.
 */
async function retryTransport<T extends { error: { message: string } | null }>(call: () => PromiseLike<T>): Promise<T> {
  let result = await call();
  for (let attempt = 0; attempt < 3 && result.error?.message.includes("fetch failed"); attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    result = await call();
  }
  return result;
}

interface EntryRow {
  user_id: string;
  points: number;
  rank: number;
  frozen_display_name: string | null;
}

describe.skipIf(!hasRealCredentials)("rebuild_global_leaderboard — real DB", () => {
  let admin: import("@supabase/supabase-js").SupabaseClient;
  let seasonId: string;
  const userIds: string[] = [];
  const tag = `t218-${Date.now()}`;

  async function makeUser(label: string, displayName: string | null) {
    const { data, error } = await retryTransport(() =>
      admin
        .from("user")
        .insert({ email: `${tag}-${label}@laju-test.local`, username: `${tag}${label}`, display_name: displayName })
        .select("id")
        .single()
    );
    if (error || !data) throw new Error(`user insert failed: ${error?.message}`);
    userIds.push(data.id);
    return data.id as string;
  }

  async function addRun(userId: string, status: string, amount: number, type = "run") {
    const { data: run, error } = await retryTransport(() =>
      admin.from("run").insert({ user_id: userId, status, anomaly_flags: [] }).select("id").single()
    );
    if (error || !run) throw new Error(`run insert failed: ${error?.message}`);
    await addTransaction(userId, run.id, amount, type);
    return run.id as string;
  }

  async function addTransaction(userId: string, runId: string, amount: number, type = "run") {
    const { error } = await retryTransport(() =>
      admin.from("point_transaction").insert({ user_id: userId, run_id: runId, season_id: seasonId, amount, type })
    );
    if (error) throw new Error(`transaction insert failed: ${error.message}`);
  }

  async function rebuild() {
    const { error } = await retryTransport(() => admin.rpc("rebuild_global_leaderboard"));
    if (error) throw new Error(`rebuild failed: ${error.message}`);
  }

  async function entries(): Promise<EntryRow[]> {
    const { data, error } = await admin
      .from("leaderboard_entry")
      .select("user_id, points, rank, frozen_display_name")
      .eq("season_id", seasonId)
      .eq("scope_type", "global")
      .in("user_id", userIds);
    if (error) throw new Error(`entries read failed: ${error.message}`);
    return (data ?? []) as EntryRow[];
  }

  beforeAll(async () => {
    const { createClient } = await import("@supabase/supabase-js");
    admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: season, error } = await admin.from("season").select("id").eq("status", "active").single();
    if (error || !season) throw new Error("no active season — T2.17's seed is required");
    seasonId = season.id;
  }, 30000);

  afterAll(async () => {
    if (userIds.length > 0) {
      await admin.from("leaderboard_entry").delete().in("user_id", userIds);
      await admin.from("point_transaction").delete().in("user_id", userIds);
      await admin.from("run").delete().in("user_id", userIds);
      await admin.from("user").delete().in("id", userIds);
    }
    await rebuild(); // leave the real board consistent with the real (test-free) data
  }, 30000);

  it("ranks by season points, ties share a rank, and writes the explicit global scope row", async () => {
    const a = await makeUser("a", "Alice");
    const b = await makeUser("b", "Budi");
    const c = await makeUser("c", null); // no display_name → falls back to username
    await addRun(a, "validated", 300);
    await addRun(b, "approved", 200);
    await addRun(b, "validated", 100);
    await addRun(c, "validated", 100);

    await rebuild();

    const rows = await entries();
    const byUser = new Map(rows.map((r) => [r.user_id, r]));
    expect(byUser.get(a)).toMatchObject({ points: 300, frozen_display_name: "Alice" });
    expect(byUser.get(b)).toMatchObject({ points: 300, frozen_display_name: "Budi" }); // 200 approved + 100 validated
    expect(byUser.get(a)?.rank).toBe(byUser.get(b)?.rank); // tied on 300
    expect(byUser.get(c)?.rank).toBeGreaterThan(byUser.get(a)?.rank ?? 0);
    expect(byUser.get(c)?.frozen_display_name).toBe(`${tag}c`);

    const { data: scope } = await admin
      .from("leaderboard_scope")
      .select("user_count, insufficient_data, scope_id")
      .eq("season_id", seasonId)
      .eq("scope_type", "global")
      .single();
    expect(scope).toMatchObject({ scope_id: "GLOBAL", insufficient_data: false });
    const { count } = await admin
      .from("leaderboard_entry")
      .select("id", { count: "exact", head: true })
      .eq("season_id", seasonId)
      .eq("scope_type", "global");
    expect(scope?.user_count).toBe(count);
  }, 30000);

  it("a flagged run's points are excluded until it resolves to approved; a rejected run never counts", async () => {
    const u = await makeUser("fair", "Fair");
    const flaggedRunId = await addRun(u, "flagged", 500);
    // Rejected run the way T2.12b leaves it: original ledger row plus its compensating adjustment.
    const rejectedRunId = await addRun(u, "rejected", 400);
    await addTransaction(u, rejectedRunId, -400, "adjustment");

    await rebuild();
    expect((await entries()).find((r) => r.user_id === u)).toBeUndefined();

    await admin.from("run").update({ status: "approved" }).eq("id", flaggedRunId);
    await rebuild();
    expect((await entries()).find((r) => r.user_id === u)?.points).toBe(500); // flagged run now counts; rejected still doesn't
  }, 30000);

  it("a soft-deleted user disappears from the next rebuild", async () => {
    const u = await makeUser("gone", "Gone");
    await addRun(u, "validated", 50);
    await rebuild();
    expect((await entries()).find((r) => r.user_id === u)).toBeDefined();

    await admin.from("user").update({ deleted_at: new Date().toISOString() }).eq("id", u);
    await rebuild();
    expect((await entries()).find((r) => r.user_id === u)).toBeUndefined();
  }, 30000);

  it("is a full rebuild: running twice never duplicates rows, and frozen_display_name is a snapshot", async () => {
    const u = await makeUser("snap", "Before");
    await addRun(u, "validated", 70);
    await rebuild();
    await rebuild();
    expect((await entries()).filter((r) => r.user_id === u)).toHaveLength(1);

    await admin.from("user").update({ display_name: "After" }).eq("id", u);
    expect((await entries()).find((r) => r.user_id === u)?.frozen_display_name).toBe("Before"); // no live join

    await rebuild();
    expect((await entries()).find((r) => r.user_id === u)?.frozen_display_name).toBe("After");
  }, 30000);

  it("is not callable by anon (internal job, not a public RPC)", async () => {
    const { createClient } = await import("@supabase/supabase-js");
    const anon = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const { error } = await anon.rpc("rebuild_global_leaderboard");
    expect(error).not.toBeNull();
  });
});
