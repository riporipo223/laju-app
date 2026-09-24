import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { errorResponse, productionDeps } from "@/lib/club-war/http";

/**
 * T4.2b: the caller's club's Club War Record — wins, losses and net wins (§4.20 AC10) over ended wars.
 * Dissolved challenges never count (§4.19 AC7/AC12). All-time: filtering to the current period
 * (Season 1 / 60-day cycles, §4.20 AC8-AC9) belongs to T4.17b's precompute, not here.
 */
export async function GET(request: Request) {
  const auth = await requireUser(request, "clubwar.get");
  if (isAuthFailure(auth)) return auth.response;

  const { repo } = productionDeps();
  const membership = await repo.getMembership(auth.user.id);
  if (!membership) return errorResponse("not_in_club");

  const ended = (await repo.listWarsForClub(membership.clubId)).filter((w) => w.status === "ended");
  const wins = ended.filter((w) => w.winnerClubId === membership.clubId).length;
  const losses = ended.length - wins;
  return NextResponse.json({ club_id: membership.clubId, wins, losses, net_wins: wins - losses });
}
