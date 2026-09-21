/**
 * tech-spec.md §2.5 — Season League ("tier"). Values are lowercase machine names (`gold`); display names are the client's job. A pure function of the points earned in ONE season; never stored, so it cannot
 * drift from the ledger. Bands are half-open `[min, max)` and are config, not inline literals.
 *
 * v1 starting values from the point formula and a ~91-day season, NOT from real user data — recalibrate after a season or two
 * (target roughly 40% / 35% / 20% / 5%). Do not present them as final.
 */

export type League = "bronze" | "silver" | "gold" | "platinum";

export interface LeagueBand {
  league: League;
  /** Inclusive lower bound of `season_points`. */
  minPoints: number;
}

/** Ascending by `minPoints`; the first band's `minPoints` must be 0 so every user always has a league. */
export const LEAGUE_BANDS: readonly LeagueBand[] = [
  { league: "bronze", minPoints: 0 },
  { league: "silver", minPoints: 80 },
  { league: "gold", minPoints: 250 },
  { league: "platinum", minPoints: 600 },
];

export function leagueFor(seasonPoints: number, bands: readonly LeagueBand[] = LEAGUE_BANDS): League {
  let current = bands[0]!.league;
  for (const band of bands) {
    if (seasonPoints >= band.minPoints) current = band.league;
  }
  return current;
}
