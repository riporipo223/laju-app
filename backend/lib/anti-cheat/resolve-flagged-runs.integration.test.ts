/**
 * T2.13 — Layer 3 (Integration): the confidence-based resolution lifecycle (T2.12b/T2.12f) exercised
 * against a real Supabase project, no mocks. `resolve-flagged-runs.test.ts` (Layer 1) already covers the
 * same logic with mocked DB calls for speed; this file proves it against real Postgres rows, matching this
 * task's own DoD wording ("LOW-confidence flagged → approved auto-resolve via the actual Cron job... HIGH-
 * confidence flagged runs confirmed to NEVER auto-resolve... manual flagged → rejected override produces a
 * correct compensating transaction").
 *
 * `autoResolveOverdueLowConfidenceFlags` is called directly rather than over HTTP against the deployed
 * `/api/cron/resolve-flagged-runs` route — it's the exact function that route calls (T2.12f's own DoD
 * already separately proved the HTTP route itself works, live, against a real deployment); calling it
 * directly here avoids needing `CRON_SECRET` and a stable deployed URL as additional CI secrets for
 * something this suite doesn't otherwise depend on.
 *
 * Requires real credentials, same as `route.integration.test.ts` (GitHub Actions repo secrets, added
 * 2026-09-18) — skips gracefully when absent.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const hasRealCredentials = Boolean(
  process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

describe.skipIf(!hasRealCredentials)("Resolution lifecycle (T2.12b/T2.12f) — real DB, no mocks", () => {
  let authUserId: string;
  let userId: string;
  let seasonId: string;
  let supabaseAdmin: import("@supabase/supabase-js").SupabaseClient;
  let resolveFlaggedRun: typeof import("./resolve-flagged-runs").resolveFlaggedRun;
  let autoResolveOverdueLowConfidenceFlags: typeof import("./resolve-flagged-runs").autoResolveOverdueLowConfidenceFlags;

  beforeAll(async () => {
    const { createClient } = await import("@supabase/supabase-js");
    supabaseAdmin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const email = `t213-resolve-${Date.now()}@laju-test.local`;
    const { data: created, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password: crypto.randomUUID(),
      email_confirm: true,
    });
    if (createError || !created.user) throw new Error(`Could not create test auth user: ${createError?.message}`);
    authUserId = created.user.id;

    const { data: userRow, error: userError } = await supabaseAdmin
      .from("user")
      .insert({ auth_user_id: authUserId, email, username: `t213resolve${Date.now()}` })
      .select("id")
      .single();
    if (userError || !userRow) throw new Error(`Could not create test user row: ${userError?.message}`);
    userId = userRow.id;

    const { data: season, error: seasonError } = await supabaseAdmin
      .from("season")
      .select("id")
      .eq("status", "active")
      .maybeSingle();
    if (seasonError || !season) throw new Error(`Could not find active season: ${seasonError?.message}`);
    seasonId = season.id;

    ({ resolveFlaggedRun, autoResolveOverdueLowConfidenceFlags } = await import("./resolve-flagged-runs"));
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

  async function seedFlaggedRun(confidence: "low" | "high", ageHours: number, points: number) {
    const { data: run, error } = await supabaseAdmin
      .from("run")
      .insert({
        user_id: userId,
        status: "flagged",
        flag_confidence: confidence,
        anomaly_flags: ["pace_cap_exceeded"],
        final_points_awarded: points,
        created_at: new Date(Date.now() - ageHours * 60 * 60 * 1000).toISOString(),
        updated_at: new Date(Date.now() - ageHours * 60 * 60 * 1000).toISOString(),
      })
      .select("id")
      .single();
    if (error || !run) throw new Error(`Could not seed flagged run: ${error?.message}`);
    await supabaseAdmin
      .from("point_transaction")
      .insert({ user_id: userId, run_id: run.id, season_id: seasonId, amount: points, type: "run" });
    return run.id as string;
  }

  it("a LOW-confidence flagged run past REVIEW_WINDOW_LOW auto-resolves to approved via the real function", async () => {
    const runId = await seedFlaggedRun("low", 50, 5);
    const resolved = await autoResolveOverdueLowConfidenceFlags();
    expect(resolved).toContain(runId);

    const { data: run } = await supabaseAdmin
      .from("run")
      .select("status, resolved_via, resolved_at, flag_confidence")
      .eq("id", runId)
      .single();
    expect(run).toMatchObject({ status: "approved", resolved_via: "auto", flag_confidence: "low" });
    expect(run!.resolved_at).not.toBeNull();
  });

  it("a HIGH-confidence flagged run, however old, is never auto-resolved", async () => {
    const runId = await seedFlaggedRun("high", 500, 8);
    await autoResolveOverdueLowConfidenceFlags();

    const { data: run } = await supabaseAdmin
      .from("run")
      .select("status, resolved_via, resolved_at")
      .eq("id", runId)
      .single();
    expect(run).toMatchObject({ status: "flagged", resolved_via: null, resolved_at: null });
  });

  it("a manual override to rejected writes a correct compensating PointTransaction, original untouched", async () => {
    const runId = await seedFlaggedRun("low", 1, 10);
    await resolveFlaggedRun(runId, "rejected", "manual");

    const { data: run } = await supabaseAdmin
      .from("run")
      .select("status, resolved_via, final_points_awarded")
      .eq("id", runId)
      .single();
    expect(run).toMatchObject({ status: "rejected", resolved_via: "manual", final_points_awarded: 0 });

    const { data: transactions } = await supabaseAdmin
      .from("point_transaction")
      .select("amount, type")
      .eq("run_id", runId)
      .order("created_at", { ascending: true });
    expect(transactions).toEqual([
      { amount: 10, type: "run" },
      { amount: -10, type: "adjustment" },
    ]);
  });
});
