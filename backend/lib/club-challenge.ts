/**
 * Circle Challenge progress/ranking/status computation (product-spec.md §4.24 AC13, "Full mechanics"
 * decided 2026-09-26). Pure functions, unit-tested directly — the route (`GET /api/clubs/[id]/
 * challenge/route.ts`) only fetches data and calls these, same split `lib/streak.ts` uses between
 * `priorStreakDays` (pure) and `streakDaysFor` (DB-integration).
 */

export interface MembershipStint {
  userId: string;
  joinedAt: Date;
  leftAt: Date | null;
}

export interface QualifyingRun {
  userId: string;
  startedAt: Date;
  distanceMeters: number;
  durationSeconds: number;
}

export interface ChallengeProgress {
  collectiveTotal: number;
  ranking: { userId: string; total: number }[];
}

/** Whether `runStartedAt` falls inside ANY of a user's membership stints for this club — a user can
 * join, leave, and rejoin, so this checks every stint, not just the current or most recent one. */
function isWithinAnyStint(stints: MembershipStint[], runStartedAt: Date): boolean {
  return stints.some((stint) => runStartedAt >= stint.joinedAt && (stint.leftAt === null || runStartedAt <= stint.leftAt));
}

/**
 * `runs` must already be pre-filtered by the caller to: qualifying status (`validated`/`approved`/
 * `flagged`), clearing the ADR-0009 distance gate, and inside the challenge's own [created_at,
 * min(now, deadline)] window — this function only applies the membership-stint eligibility rule on
 * top of that.
 *
 * The collective total sums EVERY eligible run regardless of current membership (a departed member's
 * past contribution keeps counting, product-spec.md AC13) — `currentMemberIds` only filters the
 * separate individual ranking, never the total.
 */
export function computeChallengeProgress(params: {
  targetType: "distance" | "duration";
  history: MembershipStint[];
  currentMemberIds: Set<string>;
  runs: QualifyingRun[];
}): ChallengeProgress {
  const stintsByUser = new Map<string, MembershipStint[]>();
  for (const stint of params.history) {
    const existing = stintsByUser.get(stint.userId);
    if (existing) {
      existing.push(stint);
    } else {
      stintsByUser.set(stint.userId, [stint]);
    }
  }

  let collectiveTotal = 0;
  const perUserTotal = new Map<string, number>();
  for (const run of params.runs) {
    const stints = stintsByUser.get(run.userId) ?? [];
    if (!isWithinAnyStint(stints, run.startedAt)) continue;
    const value = params.targetType === "distance" ? run.distanceMeters : run.durationSeconds;
    collectiveTotal += value;
    perUserTotal.set(run.userId, (perUserTotal.get(run.userId) ?? 0) + value);
  }

  const ranking = [...perUserTotal.entries()]
    .filter(([userId]) => params.currentMemberIds.has(userId))
    .map(([userId, total]) => ({ userId, total }))
    .sort((a, b) => b.total - a.total);

  return { collectiveTotal, ranking };
}

export type ChallengeStatus = "active" | "target_reached" | "closed_success" | "closed_missed" | "cancelled";

/**
 * A challenge closes only at its deadline, never early (product-spec.md AC13: reaching the target
 * before the deadline does not end it) — `target_reached` is a display-only milestone while still
 * open. `cancelled` is terminal and short-circuits everything else, since the owner can cancel at
 * any time regardless of deadline/target state.
 */
export function computeChallengeStatus(params: {
  storedStatus: string;
  deadline: Date;
  targetValue: number;
  collectiveTotal: number;
  now: Date;
}): ChallengeStatus {
  if (params.storedStatus === "cancelled") return "cancelled";
  const targetMet = params.collectiveTotal >= params.targetValue;
  const deadlinePassed = params.now.getTime() >= params.deadline.getTime();
  if (!deadlinePassed) return targetMet ? "target_reached" : "active";
  return targetMet ? "closed_success" : "closed_missed";
}
