/**
 * T2.22 — Layer 3: `DELETE /api/account` against the real Supabase project with genuine Auth identities.
 * Every DoD item that can be checked server-side is checked here field by field against real rows — the
 * anonymization, the untouched ledger, the flagged-run resolution, the dead pre-deletion token, and the
 * leaderboard exclusion — not asserted in prose. Skips without credentials.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createTestAuthUser } from "@/test-support/auth";

const hasRealCredentials = Boolean(
  process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

// CI-runner transport blips (`TypeError: fetch failed`) are retried; real errors surface at once.
async function retryTransport<T extends { error: { message: string } | null }>(call: () => PromiseLike<T>): Promise<T> {
  let result = await call();
  for (let attempt = 0; attempt < 3 && result.error?.message.includes("fetch failed"); attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    result = await call();
  }
  return result;
}

const SECRET_ROUTE = [{ lat: -6.2, lng: 106.8, timestamp: "2026-09-08T06:00:00Z", elevation: 45 }];

describe.skipIf(!hasRealCredentials)("DELETE /api/account — real DB + real Auth", () => {
  let admin: import("@supabase/supabase-js").SupabaseClient;
  let anon: import("@supabase/supabase-js").SupabaseClient;
  let seasonId: string;
  let DELETE: (request: Request) => Promise<Response>;
  let completeProfile: (request: Request) => Promise<Response>;
  let getProgress: (request: Request) => Promise<Response>;
  const authIds: string[] = [];
  const userIds: string[] = [];
  const tag = `t222-${Date.now()}`;

  async function makeIdentity(label: string) {
    const email = `${tag}-${label}@laju-test.local`;
    const session = await createTestAuthUser(admin, anon, email);
    authIds.push(session.authUserId);
    return { authId: session.authUserId, email, jwt: session.accessToken };
  }

  async function makeProfile(identity: { authId: string; email: string }, label: string) {
    const { data, error } = await retryTransport(() =>
      admin
        .from("user")
        .insert({
          auth_user_id: identity.authId,
          email: identity.email,
          username: `${tag}${label}`,
          display_name: `Name ${label}`,
          avatar_url: "https://example.com/a.png",
        })
        .select("id")
        .single()
    );
    if (error || !data) throw new Error(`user insert failed: ${error?.message}`);
    userIds.push(data.id);
    return data.id as string;
  }

  async function addRun(userId: string, status: string, amount: number, extra: Record<string, unknown> = {}) {
    const { data: run, error } = await retryTransport(() =>
      admin
        .from("run")
        .insert({ user_id: userId, status, anomaly_flags: [], gps_route: SECRET_ROUTE, final_points_awarded: amount, ...extra })
        .select("id")
        .single()
    );
    if (error || !run) throw new Error(`run insert failed: ${error?.message}`);
    const { data: tx, error: txError } = await retryTransport(() =>
      admin
        .from("point_transaction")
        .insert({ user_id: userId, run_id: run.id, season_id: seasonId, amount, type: "run" })
        .select("id")
        .single()
    );
    if (txError || !tx) throw new Error(`transaction insert failed: ${txError?.message}`);
    return { runId: run.id as string, txId: tx.id as string };
  }

  const del = (jwt: string) =>
    DELETE(new Request("https://example.com/api/account", { method: "DELETE", headers: { authorization: `Bearer ${jwt}` } }));

  async function authUserExists(authId: string) {
    const { data } = await admin.auth.admin.getUserById(authId);
    return Boolean(data.user);
  }

  beforeAll(async () => {
    const { createClient } = await import("@supabase/supabase-js");
    admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    anon = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const { data: season, error } = await admin.from("season").select("id").eq("status", "active").single();
    if (error || !season) throw new Error("no active season — T2.17's seed is required");
    seasonId = season.id;
    ({ DELETE } = await import("./route"));
    ({ POST: completeProfile } = await import("../profile/complete/route"));
    ({ GET: getProgress } = await import("../users/me/progress/route"));
  }, 60000);

  afterAll(async () => {
    if (userIds.length > 0) {
      await admin.from("leaderboard_entry").delete().in("user_id", userIds);
      await admin.from("point_transaction").delete().in("user_id", userIds);
      await admin.from("run").delete().in("user_id", userIds);
      await admin.from("user").delete().in("id", userIds);
    }
    for (const id of authIds) await admin.auth.admin.deleteUser(id);
    await admin.rpc("rebuild_global_leaderboard");
  }, 60000);

  it("rejects unauthenticated requests", async () => {
    const res = await DELETE(new Request("https://example.com/api/account", { method: "DELETE" }));
    expect(res.status).toBe(401);
  });

  it("anonymizes every personal field, keeps the ledger untouched, and kills the Auth identity", async () => {
    const identity = await makeIdentity("main");
    const userId = await makeProfile(identity, "main");
    const validated = await addRun(userId, "validated", 100);
    const flagged = await addRun(userId, "flagged", 50, { flag_confidence: "low" });

    const res = await del(identity.jwt);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ deleted: true });

    // --- the `user` row, every field of database-api-spec.md §2.1b ---
    const { data: user } = await admin.from("user").select("*").eq("id", userId).single();
    expect(user?.deleted_at).not.toBeNull();
    expect(user?.email).toMatch(/^deleted\+[0-9a-f-]{36}@laju\.invalid$/);
    expect(user?.email).not.toBe(identity.email);
    for (const field of ["username", "display_name", "avatar_url"]) {
      expect(user?.[field], `${field} must be cleared`).toBeNull();
    }
    // retained on purpose (derived from the immutable ledger), never cleared
    expect(user?.total_points).toBe(100); // 100 validated + (50 flagged − 50 compensating)
    expect(user?.current_level).not.toBeNull();
    expect(user?.trust_score).not.toBeNull();
    expect(user?.id).toBe(userId); // row kept so PointTransaction.user_id stays valid

    // --- Auth identity gone ---
    expect(await authUserExists(identity.authId)).toBe(false);

    // --- ledger: original rows untouched, one compensating adjustment added, nothing deleted ---
    const { data: ledger } = await admin.from("point_transaction").select("id, amount, type").eq("user_id", userId);
    const byId = new Map((ledger ?? []).map((row) => [row.id, row]));
    expect(byId.get(validated.txId)).toMatchObject({ amount: 100, type: "run" });
    expect(byId.get(flagged.txId)).toMatchObject({ amount: 50, type: "run" });
    expect(ledger).toHaveLength(3);
    expect((ledger ?? []).filter((row) => row.type === "adjustment").map((row) => row.amount)).toEqual([-50]);

    // --- runs: routes nulled, rows kept, the flagged one terminally rejected ---
    const { data: runs } = await admin.from("run").select("id, status, gps_route, resolved_via").eq("user_id", userId);
    expect(runs).toHaveLength(2);
    for (const run of runs ?? []) expect(run.gps_route).toBeNull();
    const flaggedAfter = (runs ?? []).find((run) => run.id === flagged.runId);
    expect(flaggedAfter).toMatchObject({ status: "rejected", resolved_via: "manual" });
    expect((runs ?? []).find((run) => run.id === validated.runId)?.status).toBe("validated");
  }, 60000);

  it("a pre-deletion JWT is dead: profile/complete and a requireUser endpoint both answer 401", async () => {
    const identity = await makeIdentity("token");
    await makeProfile(identity, "token");
    expect((await del(identity.jwt)).status).toBe(200);

    const profile = await completeProfile(
      new Request("https://example.com/api/profile/complete", {
        method: "POST",
        headers: { authorization: `Bearer ${identity.jwt}`, "content-type": "application/json" },
        body: JSON.stringify({ username: "revived" }),
      })
    );
    expect(profile.status).toBe(401);
    const progress = await getProgress(
      new Request("https://example.com/api/users/me/progress", { headers: { authorization: `Bearer ${identity.jwt}` } })
    );
    expect(progress.status).toBe(401);
  }, 60000);

  it("a half-deleted account (soft-deleted, Auth identity still alive) cannot be revived, and a retry finishes the job", async () => {
    const identity = await makeIdentity("half");
    const userId = await makeProfile(identity, "half");
    // The state a failure at the final step would leave behind: row soft-deleted, identity + JWT still valid.
    await admin.from("user").update({ deleted_at: new Date().toISOString(), username: null }).eq("id", userId);

    const revive = await completeProfile(
      new Request("https://example.com/api/profile/complete", {
        method: "POST",
        headers: { authorization: `Bearer ${identity.jwt}`, "content-type": "application/json" },
        body: JSON.stringify({ username: "revived" }),
      })
    );
    expect(revive.status).toBe(401); // the B7-10 hole: without the guard this would re-populate `username`
    const { data: still } = await admin.from("user").select("username").eq("id", userId).single();
    expect(still?.username).toBeNull();

    expect(await authUserExists(identity.authId)).toBe(true);
    expect((await del(identity.jwt)).status).toBe(200); // idempotent retry completes the deletion
    expect(await authUserExists(identity.authId)).toBe(false);
  }, 60000);

  it("an identity that never completed its profile can still delete its account", async () => {
    const identity = await makeIdentity("noprofile");
    expect((await del(identity.jwt)).status).toBe(200);
    expect(await authUserExists(identity.authId)).toBe(false);
  }, 60000);

  it("a soft-deleted user never appears in a leaderboard rebuild after deletion (T2.18's real exclusion filter)", async () => {
    const identity = await makeIdentity("board");
    const userId = await makeProfile(identity, "board");
    await addRun(userId, "validated", 200);
    await admin.rpc("rebuild_global_leaderboard");
    const before = await admin.from("leaderboard_entry").select("user_id").eq("user_id", userId);
    expect(before.data).toHaveLength(1); // proves the user WAS on the board, so the absence below means something

    expect((await del(identity.jwt)).status).toBe(200);
    await admin.rpc("rebuild_global_leaderboard");

    const after = await admin.from("leaderboard_entry").select("user_id").eq("user_id", userId);
    expect(after.data).toEqual([]);
  }, 60000);
});
