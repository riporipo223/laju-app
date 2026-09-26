/**
 * Circle analytics aggregation (product-spec.md §4.24 AC12: rolling 30-day window, top-5). Pure
 * function, unit-tested directly — the route (`GET /api/clubs/[id]/analytics/route.ts`) only fetches
 * already-filtered runs (qualifying status + ADR-0009 distance gate + within the window + current
 * members only) and calls this.
 *
 * Top contributors are ranked by distance, not points — a judgment call, not a documented product
 * decision (product-spec.md lists "aggregate total distance and total points" without specifying a
 * sort key for the separate top-N list). Distance is this app's primary, always-shown metric
 * everywhere else (run summary's hero stat, design-notes.md §5), so it's the more natural default;
 * flag this choice to the PM if a specific sort was actually intended.
 */

export interface AnalyticsRun {
  userId: string;
  distanceMeters: number;
  finalPointsAwarded: number | null;
}

export interface ClubAnalytics {
  totalDistanceMeters: number;
  totalPoints: number;
  activeMemberCount: number;
  topContributors: { userId: string; distanceMeters: number; points: number }[];
}

export function computeClubAnalytics(params: { runs: AnalyticsRun[]; topN: number }): ClubAnalytics {
  let totalDistanceMeters = 0;
  let totalPoints = 0;
  const perUser = new Map<string, { distanceMeters: number; points: number }>();

  for (const run of params.runs) {
    totalDistanceMeters += run.distanceMeters;
    const points = run.finalPointsAwarded ?? 0;
    totalPoints += points;

    const existing = perUser.get(run.userId) ?? { distanceMeters: 0, points: 0 };
    existing.distanceMeters += run.distanceMeters;
    existing.points += points;
    perUser.set(run.userId, existing);
  }

  const topContributors = [...perUser.entries()]
    .map(([userId, totals]) => ({ userId, distanceMeters: totals.distanceMeters, points: totals.points }))
    .sort((a, b) => b.distanceMeters - a.distanceMeters)
    .slice(0, params.topN);

  return {
    totalDistanceMeters,
    totalPoints,
    activeMemberCount: perUser.size,
    topContributors,
  };
}
