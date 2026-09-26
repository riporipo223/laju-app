/**
 * T2.11: tech-spec.md §2.4's `trust_multiplier` formula (defined 2026-09-17). Turns repeated flagging into
 * a graduated consequence instead of a binary ban.
 *
 * `computeTrustMultiplier` is the pure formula — the thing every DoD item can be unit-tested against
 * directly. `trustMultiplierForUser`/`recomputeAndPersistTrustScore` are the DB-querying wrapper, scoped to
 * a single user's rolling 30-day window.
 */

import { SEVERE_SPEED_VIOLATION_FLAG } from "./anti-cheat/severe-speed-violation";
import { supabaseAdmin } from "./supabase";

export const TRUST_SCORE_WINDOW_DAYS = 30;
export const HIGH_FLAG_DECAY = 0.1;
export const LOW_FLAG_DECAY = 0.05;
export const CLEAN_RUN_RECOVERY = 0.02;
export const TRUST_SCORE_FLOOR = 0.3;
export const TRUST_SCORE_CEILING = 1.0;
/**
 * T4.22 (product-spec.md §4.29 AC4): "heavier than the standard HIGH-flag deduction." 2x
 * `HIGH_FLAG_DECAY`, chosen as a clearly-larger round multiple rather than an arbitrary
 * in-between value, so the "heavier" intent reads unambiguously even before real calibration
 * data exists. **Starting value, not final** — needs its own calibration pass against real
 * cheating-attempt data, same status as `HIGH_FLAG_DECAY` itself and the pace-multiplier/
 * streak-bonus constants in tech-spec.md §2.3 (not decided in product-spec.md §4.29, explicitly
 * flagged there as a separate calibration item).
 */
export const SEVERE_SPEED_VIOLATION_DECAY = 0.2;

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
  /** T4.22: runs forced to `rejected` by the severe speed-violation check (`SEVERE_SPEED_VIOLATION_FLAG`
   * in `anomaly_flags`) — decays separately from and more than `highFlagCount`, never double-counted
   * with it (`fetchTrustScoreInputs` checks this first, mutually exclusive with the flag_confidence
   * branches). Optional, defaults to 0 — every pre-existing call site/test predates this outcome. */
  severeSpeedViolationCount?: number;
}

/** Pure formula — tech-spec.md §2.4 plus T4.22's severe-violation addition (product-spec.md §4.29 AC4). No I/O, fully deterministic. */
export function computeTrustMultiplier(inputs: TrustScoreInputs): number {
  const raw =
    1.0 -
    HIGH_FLAG_DECAY * inputs.highFlagCount -
    LOW_FLAG_DECAY * inputs.lowDecayFlagCount -
    SEVERE_SPEED_VIOLATION_DECAY * (inputs.severeSpeedViolationCount ?? 0) +
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
  let severeSpeedViolationCount = 0;

  for (const row of rows) {
    // T4.22: checked first and mutually exclusive with the flag_confidence branches below — a
    // severe-violation run is always `rejected` with `flag_confidence=null` (status-resolution.ts's
    // own override), so it would otherwise silently fall through every branch and count as neither
    // HIGH nor clean, which is wrong (it must decay, and MORE than HIGH).
    if (Array.isArray(row.anomaly_flags) && row.anomaly_flags.includes(SEVERE_SPEED_VIOLATION_FLAG)) {
      severeSpeedViolationCount++;
    } else if (row.flag_confidence === "high") {
      highFlagCount++;
    } else if (row.flag_confidence === "low") {
      const autoApproved = row.status === "approved" && row.resolved_via === "auto";
      if (!autoApproved) lowDecayFlagCount++;
    } else if (row.status === "validated" && Array.isArray(row.anomaly_flags) && row.anomaly_flags.length === 0) {
      cleanRunCount++;
    }
  }

  return { highFlagCount, lowDecayFlagCount, cleanRunCount, severeSpeedViolationCount };
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
