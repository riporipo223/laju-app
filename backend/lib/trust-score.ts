/**
 * T2.11: tech-spec.md §2.4's `trust_multiplier` formula (defined 2026-09-17). Turns repeated flagging into
 * a graduated consequence instead of a binary ban.
 *
 * `computeTrustMultiplier` is the pure formula — the thing every DoD item can be unit-tested against
 * directly. `trustMultiplierForUser`/`recomputeAndPersistTrustScore` are the DB-querying wrapper, scoped to
 * a single user's rolling 30-day window.
 */

import { supabaseAdmin } from "./supabase";

export const TRUST_SCORE_WINDOW_DAYS = 30;
export const HIGH_FLAG_DECAY = 0.1;
export const LOW_FLAG_DECAY = 0.05;
export const CLEAN_RUN_RECOVERY = 0.02;
export const TRUST_SCORE_FLOOR = 0.3;
export const TRUST_SCORE_CEILING = 1.0;

export interface TrustScoreInputs {
  /** Runs with flag_confidence='high' in the window. HIGH never auto-resolves, so every one counts,
   * regardless of current status (tech-spec.md §2.4: "setiap flag HIGH selalu dihitung"). */
  highFlagCount: number;
  /** Runs with flag_confidence='low' in the window that did NOT end in auto-approve — still-flagged,
   * manually-approved, or manually-rejected LOW flags all count. Only resolved_via='auto' is exempt. */
  lowDecayFlagCount: number;
  /** Runs with status='validated' AND empty anomaly_flags in the window. An 'approved' run (previously
   * flagged, later cleared) does not count — clean means never flagged in the first place. */
  cleanRunCount: number;
}

/** Pure formula — tech-spec.md §2.4. No I/O, fully deterministic. */
export function computeTrustMultiplier(inputs: TrustScoreInputs): number {
  const raw =
    1.0 -
    HIGH_FLAG_DECAY * inputs.highFlagCount -
    LOW_FLAG_DECAY * inputs.lowDecayFlagCount +
    CLEAN_RUN_RECOVERY * inputs.cleanRunCount;
  return Math.min(TRUST_SCORE_CEILING, Math.max(TRUST_SCORE_FLOOR, raw));
}

interface WindowRow {
  status: string;
  flag_confidence: string | null;
  resolved_via: string | null;
  anomaly_flags: unknown;
}

/**
 * Window is keyed on `created_at` (when the run — and any flag on it — originated), not `resolved_at`
 * (null for a still-flagged HIGH run, which must keep counting indefinitely per tech-spec.md §2.4) and not
 * `updated_at` (would make a flag's age reset on unrelated row touches). tech-spec.md §2.4: "flag yang
 * umurnya lewat 30 hari otomatis berhenti menekan multiplier".
 */
async function fetchTrustScoreInputs(userId: string, asOf: Date): Promise<TrustScoreInputs> {
  const windowStart = new Date(asOf.getTime() - TRUST_SCORE_WINDOW_DAYS * 24 * 60 * 60 * 1000);

  const { data, error } = await supabaseAdmin
    .from("run")
    .select("status, flag_confidence, resolved_via, anomaly_flags")
    .eq("user_id", userId)
    .gte("created_at", windowStart.toISOString())
    .lte("created_at", asOf.toISOString());

  if (error) {
    throw new Error(`Could not fetch runs for trust score computation: ${error.message}`);
  }

  const rows = (data ?? []) as WindowRow[];

  let highFlagCount = 0;
  let lowDecayFlagCount = 0;
  let cleanRunCount = 0;

  for (const row of rows) {
    if (row.flag_confidence === "high") {
      highFlagCount++;
    } else if (row.flag_confidence === "low") {
      const autoApproved = row.status === "approved" && row.resolved_via === "auto";
      if (!autoApproved) lowDecayFlagCount++;
    } else if (row.status === "validated" && Array.isArray(row.anomaly_flags) && row.anomaly_flags.length === 0) {
      cleanRunCount++;
    }
  }

  return { highFlagCount, lowDecayFlagCount, cleanRunCount };
}

/** Computes the user's current multiplier without persisting anything. */
export async function trustMultiplierForUser(userId: string, asOf: Date = new Date()): Promise<number> {
  const inputs = await fetchTrustScoreInputs(userId, asOf);
  return computeTrustMultiplier(inputs);
}

/**
 * Computes and writes `User.trust_score`. Called on each validated run (this module's own caller, e.g.
 * `POST /api/runs`) and, later, whenever a flag resolves (T2.12b's DoD, not this task's — see T2.11's own
 * dependency note on why this task does not depend on T2.12b).
 */
export async function recomputeAndPersistTrustScore(userId: string, asOf: Date = new Date()): Promise<number> {
  const multiplier = await trustMultiplierForUser(userId, asOf);
  const { error } = await supabaseAdmin.from("user").update({ trust_score: multiplier }).eq("id", userId);
  if (error) {
    throw new Error(`Could not persist trust score: ${error.message}`);
  }
  return multiplier;
}
