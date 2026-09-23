/**
 * T2.22: `DELETE /api/account` (database-api-spec.md §2.1b) — App Store Guideline 5.1.1(v).
 *
 * **Order matters, and is deliberate: the Supabase Auth identity is deleted LAST.** Every earlier step is
 * idempotent, so if anything fails partway the caller can simply retry (the route authenticates with the
 * Auth identity alone, not a live `user` row, so a retry still works once `deleted_at` is set). Deleting the
 * identity first would make the JWT invalid immediately, leaving a half-deleted account with no way to
 * finish the job.
 *
 * `PointTransaction` rows are never touched (append-only ledger, tech-spec.md §4). The `user` row itself is
 * soft-deleted, not removed, so `PointTransaction.user_id` stays valid.
 */

import { resolveFlaggedRun } from "./anti-cheat/resolve-flagged-runs";
import { supabaseAdmin } from "./supabase";

interface UserRow {
  id: string;
  deleted_at: string | null;
}

export interface AccountDeletionResult {
  /** `false` when the identity never completed profile setup, so there was no `user` row to anonymize. */
  hadProfile: boolean;
  flaggedRunsRejected: number;
}

export async function deleteAccount(authUserId: string): Promise<AccountDeletionResult> {
  const { data: user, error: lookupError } = await supabaseAdmin
    .from("user")
    .select("id, deleted_at")
    .eq("auth_user_id", authUserId)
    .maybeSingle<UserRow>();
  if (lookupError) throw new Error(`Could not look up user: ${lookupError.message}`);

  let flaggedRunsRejected = 0;

  if (user) {
    // Terminal resolution of any still-`flagged` run through the SAME compensating-transaction path a manual
    // override uses (tech-spec.md §2.4.1) — nothing is left waiting on a reviewer for an account that no
    // longer exists. Done before anonymizing: resolution recomputes the user's aggregate/trust from the ledger.
    const { data: flagged, error: flaggedError } = await supabaseAdmin
      .from("run")
      .select("id")
      .eq("user_id", user.id)
      .eq("status", "flagged");
    if (flaggedError) throw new Error(`Could not list flagged runs: ${flaggedError.message}`);
    for (const run of flagged ?? []) {
      await resolveFlaggedRun(run.id, "rejected", "manual");
      flaggedRunsRejected++;
    }

    // The most sensitive server-side data: the precise route. The row stays (ledger `run_id` FK), the route goes.
    const { error: routeError } = await supabaseAdmin.from("run").update({ gps_route: null }).eq("user_id", user.id);
    if (routeError) throw new Error(`Could not clear GPS routes: ${routeError.message}`);

    if (user.deleted_at === null) {
      // Every personal field handled explicitly, never "some". `total_points`/`current_level`/`trust_score`
      // are retained on purpose: they are derived from the immutable ledger and clearing them would desync
      // the row from it; they are simply never rendered for a soft-deleted user.
      const { error: anonymizeError } = await supabaseAdmin
        .from("user")
        .update({
          deleted_at: new Date().toISOString(),
          email: `deleted+${crypto.randomUUID()}@laju.invalid`,
          username: null,
          display_name: null,
          avatar_url: null,
          // region_kecamatan/region_kabupaten_kota/region_provinsi nulling REMOVED 2026-09-23: Task B's
          // migration (20260923090000_drop_region_and_regional_scopes.sql) has now been applied to
          // production and physically dropped these columns. Nulling a nonexistent column would make
          // this UPDATE fail outright (PostgREST rejects unknown columns) — this is not a stylistic
          // cleanup, it is required for account deletion to keep working at all.
        })
        .eq("id", user.id);
      if (anonymizeError) throw new Error(`Could not anonymize user: ${anonymizeError.message}`);
    }
  }

  // Last step. An identity that is already gone is success — the end state is what was asked for.
  const { error: authError } = await supabaseAdmin.auth.admin.deleteUser(authUserId);
  if (authError && !/not.?found/i.test(authError.message)) {
    throw new Error(`Could not delete auth identity: ${authError.message}`);
  }

  return { hadProfile: user !== null, flaggedRunsRejected };
}
