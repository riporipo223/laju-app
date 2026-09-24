import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { errorResponse, productionDeps, serializeWar } from "@/lib/club-war/http";
import { createChallenge } from "@/lib/club-war/lifecycle";

/** T4.2b: the caller's club's wars — incoming/outgoing challenges, the active war, past results. */
export async function GET(request: Request) {
  const auth = await requireUser(request, "clubwar.get");
  if (isAuthFailure(auth)) return auth.response;

  const { repo } = productionDeps();
  const membership = await repo.getMembership(auth.user.id);
  if (!membership) return errorResponse("not_in_club");

  const wars = await repo.listWarsForClub(membership.clubId);
  return NextResponse.json({ club_id: membership.clubId, wars: wars.map(serializeWar) });
}

/**
 * T4.2b: send a challenge (product-spec.md §4.19). Body: `{ invited_club_ids: string[] }` (1–2 ids).
 * Until T4.20 ships, the Premium Club check always denies (`lib/club-war/premium.ts`), so this answers
 * 403 `not_premium_club` for every caller — by design.
 */
export async function POST(request: Request) {
  const auth = await requireUser(request, "clubwar.create");
  if (isAuthFailure(auth)) return auth.response;

  let body: { invited_club_ids?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse("invalid_request");
  }

  const result = await createChallenge(productionDeps(), {
    callerUserId: auth.user.id,
    invitedClubIds: body.invited_club_ids,
  });
  if (!result.ok) return errorResponse(result.error);
  return NextResponse.json({ war_id: result.value.warId, status: "pending" }, { status: 201 });
}
