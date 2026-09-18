/**
 * T2.12b: the confidence-based `flagged` → `approved`/`rejected` state machine (tech-spec.md §2.4.1).
 *
 * `resolveFlaggedRun` is the single-run state transition — used by BOTH resolution paths: LOW-confidence
 * auto-resolve (called per eligible row by `autoResolveOverdueLowConfidenceFlags`, which T2.12f will wire
 * to an actual Cron trigger — the logic alone has no scheduled owner yet, by this task's own design) and
 * the manual-override runbook (`docs/anti-cheat-resolution-runbook.md` — direct DB action, no admin UI,
 * out of v1 scope per product-spec.md §5). This task does NOT implement the immediate-`rejected`-at-
 * submission path (already T2.12a's job) or the Cron registration itself (T2.12f).
 */

import { recomputeUserPointsAggregate } from "../point-transaction";
import { supabaseAdmin } from "../supabase";
import { recomputeAndPersistTrustScore } from "../trust-score";

// tech-spec.md §2.4.1 — configuration, not hardcoded.
export const REVIEW_WINDOW_LOW_HOURS = 48;

export type ResolutionOutcome = "approved" | "rejected";
export type ResolvedVia = "auto" | "manual";

interface FlaggedRunRow {
  id: string;
  user_id: string;
  status: string;
  final_points_awarded: number;
}

export class RunNotFlaggedError extends Error {
  constructor(runId: string) {
    super(`Run ${runId} is not currently 'flagged' — cannot resolve it`);
  }
}

/**
 * Single-run resolution. `outcome='approved'` never touches the ledger — the partial `PointTransaction`
 * already written when the run was first flagged (T2.12c) becomes leaderboard-eligible simply by the
 * status change itself (tech-spec.md §2.4.1: "Poin yang sudah tercatat sejak flagged mulai ikut
 * leaderboard precompute berikutnya"). `outcome='rejected'` writes a compensating negative
 * `PointTransaction` (type `adjustment`) to net the original partial amount to zero — the original
 * transaction is never edited or deleted (append-only ledger, tech-spec.md §4).
 *
 * Always finishes by re-triggering `trust_multiplier` recomputation (T2.11's `recomputeAndPersistTrustScore`)
 * for the run's owner — required so a LOW flag's auto-approve exemption (or a manual override's lack of
 * one) takes effect immediately, not just at the user's next validated run (T2.11's own dependency note).
 */
export async function resolveFlaggedRun(
  runId: string,
  outcome: ResolutionOutcome,
  resolvedVia: ResolvedVia
): Promise<void> {
  const { data: run, error: fetchError } = await supabaseAdmin
    .from("run")
    .select("id, user_id, status, final_points_awarded")
    .eq("id", runId)
    .maybeSingle<FlaggedRunRow>();

  if (fetchError) {
    throw new Error(`Could not fetch run ${runId}: ${fetchError.message}`);
  }
  if (!run || run.status !== "flagged") {
    throw new RunNotFlaggedError(runId);
  }

  const resolvedAt = new Date().toISOString();

  if (outcome === "rejected" && run.final_points_awarded !== 0) {
    // Find the season this run's ORIGINAL partial transaction belongs to — not necessarily the currently
    // active season (a flag can resolve well after the season it was earned in has ended).
    const { data: originalTx, error: txLookupError } = await supabaseAdmin
      .from("point_transaction")
      .select("season_id")
      .eq("run_id", runId)
      .eq("type", "run")
      .maybeSingle<{ season_id: string }>();

    if (txLookupError) {
      throw new Error(`Could not look up original PointTransaction for run ${runId}: ${txLookupError.message}`);
    }
    if (!originalTx) {
      throw new Error(`Run ${runId} has final_points_awarded != 0 but no original PointTransaction found`);
    }

    const { error: adjustmentError } = await supabaseAdmin.from("point_transaction").insert({
      user_id: run.user_id,
      run_id: runId,
      season_id: originalTx.season_id,
      amount: -run.final_points_awarded,
      type: "adjustment",
    });

    if (adjustmentError) {
      throw new Error(`Could not write compensating PointTransaction for run ${runId}: ${adjustmentError.message}`);
    }
  }

  const { error: updateError } = await supabaseAdmin
    .from("run")
    .update({
      status: outcome,
      resolved_at: resolvedAt,
      resolved_via: resolvedVia,
      final_points_awarded: outcome === "rejected" ? 0 : run.final_points_awarded,
      // flag_confidence deliberately untouched — retained as a historical record (database-api-spec.md §1).
    })
    .eq("id", runId);

  if (updateError) {
    throw new Error(`Could not update run ${runId} to ${outcome}: ${updateError.message}`);
  }

  if (outcome === "rejected") {
    await recomputeUserPointsAggregate(run.user_id);
  }

  await recomputeAndPersistTrustScore(run.user_id);
}

/**
 * The LOW-confidence auto-resolve logic itself — finds every `flagged`, `flag_confidence='low'` run whose
 * `REVIEW_WINDOW_LOW_HOURS` has elapsed with no manual override, and resolves each to `approved`. HIGH-
 * confidence rows are never touched, by construction (the query itself filters on `flag_confidence='low'`).
 * T2.12f gives this an actual scheduled trigger (Vercel Cron) — calling it is not, on its own, "running."
 */
export async function autoResolveOverdueLowConfidenceFlags(asOf: Date = new Date()): Promise<string[]> {
  const cutoff = new Date(asOf.getTime() - REVIEW_WINDOW_LOW_HOURS * 60 * 60 * 1000).toISOString();

  const { data: overdueRuns, error } = await supabaseAdmin
    .from("run")
    .select("id")
    .eq("status", "flagged")
    .eq("flag_confidence", "low")
    .lt("created_at", cutoff);

  if (error) {
    throw new Error(`Could not query overdue LOW-confidence flagged runs: ${error.message}`);
  }

  const resolvedIds: string[] = [];
  for (const row of (overdueRuns ?? []) as { id: string }[]) {
    await resolveFlaggedRun(row.id, "approved", "auto");
    resolvedIds.push(row.id);
  }
  return resolvedIds;
}
