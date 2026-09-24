import { NextResponse } from "next/server";
import { productionDeps } from "@/lib/club-war/http";
import { expirePendingChallenges, finalizeDueWars } from "@/lib/club-war/lifecycle";

/**
 * T4.2b: dissolves challenges past their 24h accept deadline (§4.19 AC7) and records results for wars
 * past their 48h window (AC3-AC6, AC10). Same `CRON_SECRET` bearer pattern as resolve-flagged-runs.
 *
 * Registered in `vercel.json` on the existing daily trigger (§4.19 AC15, same as resolve-flagged-runs).
 * It checks "past the deadline", not a precise schedule, so a dissolve or result may land up to ~24h late;
 * the 48h scoring window itself stays exact. Fails until T4.2a's migration is applied.
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
  const { ended } = await finalizeDueWars(deps);
  return NextResponse.json({ dissolved, ended });
}
