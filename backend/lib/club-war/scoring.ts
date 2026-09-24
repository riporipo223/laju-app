import { MIN_DISTANCE_KM_FOR_POINTS } from "@/lib/point-calculation";
import type { ClubResult, Participant, RunRecord, RunStatus, WarClubRole, WarResult, WinReason } from "./types";

export const WAR_DURATION_MS = 48 * 60 * 60 * 1000;
export const ACCEPT_WINDOW_MS = 24 * 60 * 60 * 1000;

// §4.20 Section 1 / §4.19 AC3: the same statuses the server streak rule counts (tech-spec.md §2.2).
const COUNTED_STATUSES: ReadonlySet<RunStatus> = new Set(["validated", "approved", "flagged"]);

export function isQualifyingRun(run: RunRecord): boolean {
  return COUNTED_STATUSES.has(run.status) && run.distanceMeters >= MIN_DISTANCE_KM_FOR_POINTS * 1000;
}

export function isInWarWindow(run: RunRecord, startedAt: Date): boolean {
  const t = run.startedAt.getTime();
  return t >= startedAt.getTime() && t < startedAt.getTime() + WAR_DURATION_MS;
}

export interface ClubTally {
  clubId: string;
  role: WarClubRole;
  participantCount: number;
  activeCount: number;
  totalDistanceMeters: number;
  totalPoints: number;
  /** When the club accepted the war (inviter: when it sent the challenge) — AC5's final tie-break. */
  acceptedAtMs: number;
}

/** Tallies one club's frozen participant snapshot (§4.19 AC11) against runs inside the 48h window. */
export function summarizeClub(
  clubId: string,
  role: WarClubRole,
  participants: Participant[],
  runs: RunRecord[],
  startedAt: Date,
  acceptedAt: Date
): ClubTally {
  const memberIds = new Set(participants.filter((p) => p.clubId === clubId).map((p) => p.userId));
  const counted = runs.filter((r) => memberIds.has(r.userId) && isQualifyingRun(r) && isInWarWindow(r, startedAt));
  return {
    clubId,
    role,
    participantCount: memberIds.size,
    activeCount: new Set(counted.map((r) => r.userId)).size,
    totalDistanceMeters: counted.reduce((sum, r) => sum + r.distanceMeters, 0),
    totalPoints: counted.reduce((sum, r) => sum + (r.finalPointsAwarded ?? 0), 0),
    acceptedAtMs: acceptedAt.getTime(),
  };
}

export function participationRate(tally: ClubTally): number {
  return tally.participantCount === 0 ? 0 : tally.activeCount / tally.participantCount;
}

function leaders<T>(items: T[], score: (item: T) => number): T[] {
  const best = Math.max(...items.map(score));
  return items.filter((item) => score(item) === best);
}

/**
 * AC5's last step (PM, 2026-09-24): earliest acceptance wins, so a war always ends with a winner.
 * Club id order only separates two clubs that accepted at the identical millisecond — an
 * implementation detail so the result can never be undetermined.
 */
function earliestAccepted(tied: ClubTally[]): ClubTally {
  const first = [...tied].sort((a, b) => a.acceptedAtMs - b.acceptedAtMs || (a.clubId < b.clubId ? -1 : 1))[0];
  if (!first) throw new Error("earliestAccepted needs at least one club");
  return first;
}

/**
 * §4.19 Phase 2 rules, applied per club:
 *  - AC10: the inviter forfeits if its owner's Premium has lapsed (`inviterPremiumActive === false`).
 *  - AC6: any club with zero active participants forfeits.
 *  - AC4: among the rest, the strictly highest Participation Rate wins (one ranking, not pairwise).
 *  - AC5: a tie at the top is broken by combined distance, then combined points (order confirmed by the
 *    PM 2026-09-24), then earliest acceptance — so there is always a winner among contenders.
 * If every club forfeits, each forfeit is applied literally: all lose, there is no winner.
 */
export function decideWarResult(tallies: ClubTally[], inviterPremiumActive: boolean): WarResult {
  const forfeitReason = new Map<string, WinReason>();
  for (const t of tallies) {
    if (t.role === "inviter" && !inviterPremiumActive) forfeitReason.set(t.clubId, "forfeit_premium_lapse");
    else if (t.activeCount === 0) forfeitReason.set(t.clubId, "forfeit_inactivity");
  }

  const contenders = tallies.filter((t) => !forfeitReason.has(t.clubId));
  let winnerClubId: string | null = null;
  let winReason: WinReason | null = null;

  const [onlyContender] = contenders;
  if (contenders.length === 1 && onlyContender) {
    winnerClubId = onlyContender.clubId;
    const inviter = tallies.find((t) => t.role === "inviter");
    winReason =
      inviter && forfeitReason.get(inviter.clubId) === "forfeit_premium_lapse"
        ? "forfeit_premium_lapse"
        : "forfeit_inactivity";
  } else if (contenders.length > 1) {
    const byRate = leaders(contenders, participationRate);
    const [rateLeader] = byRate;
    if (byRate.length === 1 && rateLeader) {
      winnerClubId = rateLeader.clubId;
      winReason = "participation_rate";
    } else {
      const byDistance = leaders(byRate, (t) => t.totalDistanceMeters);
      const byPoints = byDistance.length === 1 ? byDistance : leaders(byDistance, (t) => t.totalPoints);
      winnerClubId = earliestAccepted(byPoints).clubId;
      winReason = "tie_break";
    }
  }

  const clubs: ClubResult[] = tallies.map((t) => ({
    clubId: t.clubId,
    participationRate: participationRate(t),
    outcome: t.clubId === winnerClubId ? "win" : "loss",
  }));
  return { winnerClubId, winReason, clubs };
}
