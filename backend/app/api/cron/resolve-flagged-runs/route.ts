import { NextResponse } from "next/server";
import { autoResolveOverdueLowConfidenceFlags } from "@/lib/anti-cheat/resolve-flagged-runs";

/**
 * T2.12f: the actual scheduled trigger for T2.12b's LOW-confidence auto-resolve logic (Round 2 finding
 * B-3 — the logic alone had no owning job anywhere in the architecture). Schedule lives in `vercel.json`;
 * this route only wires it to run, it does not implement the resolution logic itself (that's T2.12b's
 * `autoResolveOverdueLowConfidenceFlags`, unchanged here) and never touches HIGH-confidence flags — that
 * function's own query filters on `flag_confidence='low'`, so there is no HIGH-confidence path here to omit.
 *
 * Authenticated via `Authorization: Bearer $CRON_SECRET` — Vercel's own documented pattern for Cron routes,
 * so this endpoint can't be triggered by an arbitrary public request (it writes real ledger/trust-score
 * changes, same blast radius as any other write path in this codebase).
 *
 * `vercel.json`'s schedule is once daily (`0 0 * * *`), not the ≤12h this task's own DoD asks for — the
 * project is on Vercel's Hobby plan, which hard-rejects any cron expression running more than once per day
 * ("Upgrade to the Pro plan to unlock all Cron Jobs features"), confirmed live 2026-09-18 by a real deploy
 * attempt with a 6h schedule. User chose the daily schedule over upgrading; tracked as an open item in
 * documents/README.md rather than silently accepted as meeting the ≤12h target.
 */
export async function GET(request: Request) {
  const authHeader = request.headers.get("authorization");
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const resolvedRunIds = await autoResolveOverdueLowConfidenceFlags();

  return NextResponse.json({ resolvedCount: resolvedRunIds.length, resolvedRunIds });
}
