import { NextResponse } from "next/server";
import type { Deps, LifecycleError } from "./lifecycle";
import { isPremiumClub } from "./premium";
import { WAR_DURATION_MS } from "./scoring";
import { supabaseClubWarRepository } from "./supabase-repository";
import type { War } from "./types";

/** The only wiring routes use. Premium is always the real stub — there is no alternative checker here. */
export function productionDeps(): Deps {
  return { repo: supabaseClubWarRepository, isPremiumClub, now: () => new Date() };
}

const STATUS: Record<LifecycleError, number> = {
  invalid_request: 400,
  cannot_challenge_own_club: 400,
  not_in_club: 403,
  not_club_admin: 403,
  not_premium_club: 403,
  not_invited: 403,
  club_not_found: 404,
  war_not_found: 404,
  war_not_pending: 409,
  already_responded: 409,
};

export function errorResponse(error: LifecycleError): NextResponse {
  return NextResponse.json({ error }, { status: STATUS[error] });
}

export function serializeWar(war: War) {
  return {
    id: war.id,
    status: war.status,
    challenge_sent_at: war.challengeSentAt.toISOString(),
    accept_deadline_at: war.acceptDeadlineAt.toISOString(),
    started_at: war.startedAt?.toISOString() ?? null,
    ends_at: war.startedAt ? new Date(war.startedAt.getTime() + WAR_DURATION_MS).toISOString() : null,
    ended_at: war.endedAt?.toISOString() ?? null,
    winner_club_id: war.winnerClubId,
    win_reason: war.winReason,
    clubs: war.clubs.map((c) => ({ club_id: c.clubId, role: c.role, invite_status: c.inviteStatus })),
  };
}
