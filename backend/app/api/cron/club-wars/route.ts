import { NextResponse } from "next/server";
import { productionDeps } from "@/lib/club-war/http";
import { expirePendingChallenges, finalizeDueWars } from "@/lib/club-war/lifecycle";

/**
 * T4.2b: dissolves challenges past their 24h accept deadline (§4.19 AC7) and records results for wars
 * past their 48h window (AC3-AC6, AC10). Same `CRON_SECRET` bearer pattern as resolve-flagged-runs.
 *
 * NOT registered in `vercel.json` on purpose: the tables it reads don't exist until T4.2a's migration is
 * applied, and the Hobby plan allows only one run per day — too coarse for 24h/48h deadlines. How this
 * gets scheduled is an open decision (see the T4.2b report).
 */
export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  const authHeader = request.headers.get("authorization");
  // Without the `!secret` guard, an unset CRON_SECRET would accept the literal "Bearer undefined".
  if (!secret || authHeader !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const deps = productionDeps();
  const dissolved = await expirePendingChallenges(deps);
  const { ended, unresolvedTies } = await finalizeDueWars(deps);
  return NextResponse.json({ dissolved, ended, unresolved_ties: unresolvedTies });
}
