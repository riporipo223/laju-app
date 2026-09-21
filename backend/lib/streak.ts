import { MIN_DISTANCE_KM_FOR_POINTS } from "./point-calculation";
import { supabaseAdmin } from "./supabase";

/**
 * Server-side streak (tech-spec.md §2.2): the `streakDays` input to `calculatePoints`. Until 2026-09-21 the server
 * passed 0 — the client's estimate included the bonus, the authoritative number never did, so every run with a streak
 * ≥ 1 was "corrected" downward with no reason (found by the first real end-to-end run: estimate +2.7, awarded 1).
 *
 * Same semantics as the client's `StreakTracker` / `PersistenceController.priorStreakDays`: the number of consecutive
 * calendar days, ending YESTERDAY, on which the user had at least one qualifying run — the caller adds 1 for the run
 * being submitted if it qualifies itself. One missed day resets it. A day counts once however many runs it held.
 *
 * The server does not know the user's timezone (the client uses the device's), so day boundaries are Asia/Jakarta
 * (UTC+7, no DST) — a v1 assumption for an Indonesia-only product. A user in WITA/WIT can land one hour or two off at
 * midnight, which shows up as a small estimate-vs-final difference, never as inflated points. Revisit if the client is
 * ever made to send its own UTC offset.
 */
export const STREAK_UTC_OFFSET_MINUTES = 7 * 60;
const DAY_MS = 86_400_000;
/** `calculatePoints` caps the bonus at this many days, so there is no reason to look back further. */
export const STREAK_LOOKBACK_DAYS = 7;

/** Which Asia/Jakarta calendar day a timestamp falls on, as a day number (days since 1970-01-01, local). */
export function localDayNumber(instant: Date): number {
  return Math.floor((instant.getTime() + STREAK_UTC_OFFSET_MINUTES * 60_000) / DAY_MS);
}

/** The instant a local calendar day begins, as UTC. */
function localDayStart(dayNumber: number): Date {
  return new Date(dayNumber * DAY_MS - STREAK_UTC_OFFSET_MINUTES * 60_000);
}

/**
 * Consecutive days ending the day BEFORE `runStartedAt` that appear in `qualifyingRunStarts`, capped at
 * `STREAK_LOOKBACK_DAYS`. Pure — the query lives in `streakDaysFor`.
 */
export function priorStreakDays(qualifyingRunStarts: Date[], runStartedAt: Date): number {
  const days = new Set(qualifyingRunStarts.map(localDayNumber));
  let streak = 0;
  for (let day = localDayNumber(runStartedAt) - 1; days.has(day) && streak < STREAK_LOOKBACK_DAYS; day--) {
    streak++;
  }
  return streak;
}

/** A run only counts toward a streak if it clears the anti-grinding distance gate (ADR-0009). */
export function isStreakQualifying(distanceMeters: number): boolean {
  return distanceMeters >= MIN_DISTANCE_KM_FOR_POINTS * 1000;
}

/**
 * The streak the run being submitted now should be scored with: prior qualifying days, plus this run if it qualifies.
 * Only `validated`, `approved` and `flagged` runs extend a streak — a `rejected` run is exactly the kind of run a
 * streak must not be farmable with.
 */
export async function streakDaysFor(userId: string, runStartedAt: Date, distanceMeters: number): Promise<number> {
  const today = localDayNumber(runStartedAt);
  const { data, error } = await supabaseAdmin
    .from("run")
    .select("started_at")
    .eq("user_id", userId)
    .in("status", ["validated", "approved", "flagged"])
    .gte("distance_meters", MIN_DISTANCE_KM_FOR_POINTS * 1000)
    .gte("started_at", localDayStart(today - STREAK_LOOKBACK_DAYS).toISOString())
    .lt("started_at", localDayStart(today).toISOString())
    .limit(1000);
  if (error) throw new Error(`Could not read streak history: ${error.message}`);
  const prior = priorStreakDays(
    (data ?? []).map((row: { started_at: string }) => new Date(row.started_at)),
    runStartedAt
  );
  return prior + (isStreakQualifying(distanceMeters) ? 1 : 0);
}
