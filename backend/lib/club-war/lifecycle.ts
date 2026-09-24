import type { PremiumChecker } from "./premium";
import type { ClubWarRepository } from "./repository";
import { ACCEPT_WINDOW_MS, UnresolvableTieError, WAR_DURATION_MS, decideWarResult, summarizeClub } from "./scoring";

export interface Deps {
  repo: ClubWarRepository;
  isPremiumClub: PremiumChecker;
  now: () => Date;
}

export type LifecycleError =
  | "invalid_request"
  | "not_in_club"
  | "not_club_admin"
  | "cannot_challenge_own_club"
  | "club_not_found"
  | "not_premium_club"
  | "war_not_found"
  | "not_invited"
  | "war_not_pending"
  | "already_responded";

export type Result<T> = { ok: true; value: T } | { ok: false; error: LifecycleError };

const fail = <T>(error: LifecycleError): Result<T> => ({ ok: false, error });
const MAX_INVITED = 2; // §4.19 AC1: inviter + 1–2 invited, max 3 clubs

/** §4.19 base rule + AC1: an owner/admin of a Premium Club challenges 1–2 other clubs. */
export async function createChallenge(
  deps: Deps,
  input: { callerUserId: string; invitedClubIds: unknown }
): Promise<Result<{ warId: string }>> {
  const ids = input.invitedClubIds;
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > MAX_INVITED) return fail("invalid_request");
  if (!ids.every((id) => typeof id === "string" && id.length > 0)) return fail("invalid_request");
  const invited = [...new Set(ids as string[])];
  if (invited.length !== ids.length) return fail("invalid_request");

  const membership = await deps.repo.getMembership(input.callerUserId);
  if (!membership) return fail("not_in_club");
  if (membership.role === "member") return fail("not_club_admin");
  if (invited.includes(membership.clubId)) return fail("cannot_challenge_own_club");

  const existing = await deps.repo.existingClubIds(invited);
  if (existing.length !== invited.length) return fail("club_not_found");

  if (!(await deps.isPremiumClub(membership.clubId))) return fail("not_premium_club");

  const sentAt = deps.now();
  const warId = await deps.repo.createWar({
    inviterClubId: membership.clubId,
    invitedClubIds: invited,
    sentAt,
    deadline: new Date(sentAt.getTime() + ACCEPT_WINDOW_MS),
  });
  return { ok: true, value: { warId } };
}

export type RespondOutcome = "pending" | "active" | "dissolved";

function currentStatus(status: string): RespondOutcome {
  return status === "pending" ? "pending" : status === "dissolved" ? "dissolved" : "active";
}

/**
 * An invited club's owner/admin accepts or declines. Phase 1 (§4.19 point 4, AC2/AC7/AC12):
 * a decline, a missed 24h deadline, or the inviter losing Premium dissolves the challenge — no record
 * for anyone. When the last invited club accepts, the war goes active and the participant snapshot
 * is frozen (AC11).
 */
export async function respondToChallenge(
  deps: Deps,
  input: { callerUserId: string; warId: string; accept: unknown }
): Promise<Result<{ status: RespondOutcome }>> {
  if (typeof input.accept !== "boolean") return fail("invalid_request");

  const war = await deps.repo.getWar(input.warId);
  if (!war) return fail("war_not_found");

  const membership = await deps.repo.getMembership(input.callerUserId);
  if (!membership) return fail("not_in_club");
  const entry = war.clubs.find((c) => c.clubId === membership.clubId && c.role === "invited");
  if (!entry) return fail("not_invited");
  if (membership.role === "member") return fail("not_club_admin");
  if (war.status !== "pending") return fail("war_not_pending");

  const now = deps.now();
  if (now.getTime() >= war.acceptDeadlineAt.getTime()) {
    await deps.repo.dissolveWar(war.id);
    return { ok: true, value: { status: "dissolved" } };
  }
  if (entry.inviteStatus !== "pending") return fail("already_responded");

  if (!input.accept) {
    await deps.repo.setInviteStatus(war.id, entry.clubId, "declined", now);
    await deps.repo.dissolveWar(war.id);
    return { ok: true, value: { status: "dissolved" } };
  }

  await deps.repo.setInviteStatus(war.id, entry.clubId, "accepted", now);
  // Re-read after writing: two invited clubs accepting at once must not each see the other as pending.
  const fresh = (await deps.repo.getWar(war.id)) ?? war;
  if (fresh.status !== "pending") return { ok: true, value: { status: currentStatus(fresh.status) } };
  if (fresh.clubs.some((c) => c.role === "invited" && c.inviteStatus !== "accepted")) {
    return { ok: true, value: { status: "pending" } };
  }

  const inviter = fresh.clubs.find((c) => c.role === "inviter");
  if (!inviter || !(await deps.isPremiumClub(inviter.clubId))) {
    await deps.repo.dissolveWar(war.id);
    return { ok: true, value: { status: "dissolved" } };
  }

  if (!(await deps.repo.activateWar(war.id, now))) {
    // Lost the race to a concurrent accept, which activated (or dissolved) it — report what happened.
    const after = await deps.repo.getWar(war.id);
    return { ok: true, value: { status: currentStatus(after?.status ?? "dissolved") } };
  }
  const members = await deps.repo.listMembers(fresh.clubs.map((c) => c.clubId));
  await deps.repo.insertParticipants(war.id, members, now);
  return { ok: true, value: { status: "active" } };
}

/** AC7: pending challenges past their 24h deadline dissolve, with no record for anyone. */
export async function expirePendingChallenges(deps: Deps): Promise<string[]> {
  const ids = await deps.repo.listExpiredPendingWarIds(deps.now());
  const dissolved: string[] = [];
  for (const id of ids) {
    if (await deps.repo.dissolveWar(id)) dissolved.push(id);
  }
  return dissolved;
}

export interface FinalizeReport {
  ended: string[];
  unresolvedTies: string[];
}

/**
 * The 48-hour result (§4.19 AC3–AC6, AC10, AC13). The inviter's Premium is checked here, on demand
 * (§4.23 decided #10). A war whose clubs tie through every tie-break is left active and reported —
 * §4.19 has no rule for it, so no winner is invented.
 */
export async function finalizeDueWars(deps: Deps): Promise<FinalizeReport> {
  const now = deps.now();
  const wars = await deps.repo.listActiveWarsStartedBefore(new Date(now.getTime() - WAR_DURATION_MS));
  const report: FinalizeReport = { ended: [], unresolvedTies: [] };

  for (const war of wars) {
    const startedAt = war.startedAt;
    if (!startedAt) continue;
    const participants = await deps.repo.listParticipants(war.id);
    const runs = await deps.repo.listRuns(
      [...new Set(participants.map((p) => p.userId))],
      startedAt,
      new Date(startedAt.getTime() + WAR_DURATION_MS)
    );
    const tallies = war.clubs.map((c) => summarizeClub(c.clubId, c.role, participants, runs, startedAt));
    const inviter = war.clubs.find((c) => c.role === "inviter");
    const inviterPremiumActive = inviter ? await deps.isPremiumClub(inviter.clubId) : false;

    try {
      const result = decideWarResult(tallies, inviterPremiumActive);
      if (await deps.repo.recordResult(war.id, now, result)) report.ended.push(war.id);
    } catch (error) {
      if (error instanceof UnresolvableTieError) report.unresolvedTies.push(war.id);
      else throw error;
    }
  }
  return report;
}
