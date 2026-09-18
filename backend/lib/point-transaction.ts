/**
 * T2.12c: persists T2.12a's status resolution as the authoritative, append-only ledger record, then
 * updates `User.total_points`/`current_level` to reflect it. Only `validated`/`flagged` outcomes reach
 * here — an immediate `rejected` run never gets a `PointTransaction` (tech-spec.md §2.4.1), so the caller
 * (`POST /api/runs`) must not call this for a rejected run.
 */

import { currentLevelForPoints } from "./levels";
import { supabaseAdmin } from "./supabase";

export class NoActiveSeasonError extends Error {
  constructor() {
    super("No active season — cannot write a PointTransaction without a season_id");
  }
}

export interface RecordRunPointsResult {
  totalPoints: number;
  currentLevel: number;
}

/**
 * `User.total_points` is recomputed as `SUM(point_transaction.amount)` for this user rather than
 * incremented in place — same "recompute from the ledger, don't accumulate a separate counter" philosophy
 * as `trust-score.ts`'s `recomputeAndPersistTrustScore`, so a future bug anywhere else can never leave
 * `total_points` silently drifted from what the append-only ledger actually says. Shared by
 * `recordRunPointsAndUpdateAggregate` (new run submissions) and T2.12b's compensating-adjustment write
 * (flagged→rejected override) — both end with "the ledger changed, now make `User` agree with it."
 */
export async function recomputeUserPointsAggregate(userId: string): Promise<RecordRunPointsResult> {
  const { data: rows, error: sumError } = await supabaseAdmin
    .from("point_transaction")
    .select("amount")
    .eq("user_id", userId);

  if (sumError) {
    throw new Error(`Could not sum PointTransaction ledger: ${sumError.message}`);
  }

  const totalPoints = (rows ?? []).reduce((sum: number, row: { amount: number }) => sum + row.amount, 0);
  const currentLevel = currentLevelForPoints(totalPoints);

  const { error: updateError } = await supabaseAdmin
    .from("user")
    .update({ total_points: totalPoints, current_level: currentLevel })
    .eq("id", userId);

  if (updateError) {
    throw new Error(`Could not update User aggregate: ${updateError.message}`);
  }

  return { totalPoints, currentLevel };
}

/**
 * `amount` is the already trust-multiplied `final_points_awarded` — tech-spec.md §2.2's `final_points`
 * formula IS what gets written to the ledger, not the pre-multiplier `raw_points` (§2.4's "Poin penuh
 * (formula §2.2...)" row names §2.2, whose last line is the trust-multiplied value).
 */
export async function recordRunPointsAndUpdateAggregate(
  userId: string,
  runId: string,
  amount: number
): Promise<RecordRunPointsResult> {
  const { data: season, error: seasonError } = await supabaseAdmin
    .from("season")
    .select("id")
    .eq("status", "active")
    .maybeSingle<{ id: string }>();

  if (seasonError) {
    throw new Error(`Could not look up active season: ${seasonError.message}`);
  }
  if (!season) {
    throw new NoActiveSeasonError();
  }

  const { error: insertError } = await supabaseAdmin.from("point_transaction").insert({
    user_id: userId,
    run_id: runId,
    season_id: season.id,
    amount,
    type: "run",
  });

  if (insertError) {
    throw new Error(`Could not write PointTransaction: ${insertError.message}`);
  }

  return recomputeUserPointsAggregate(userId);
}
