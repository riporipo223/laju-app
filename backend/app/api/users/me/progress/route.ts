import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { pointsToNextLevel } from "@/lib/levels";
import { supabaseAdmin } from "@/lib/supabase";

interface ProgressRow {
  total_points: number;
  current_level: number;
  trust_score: number;
}

/**
 * T2.15: database-api-spec.md §2.3. `total_points`/`current_level` are read straight from `User` rather
 * than recomputed from `PointTransaction` here — T2.12c's `recomputeUserPointsAggregate` already keeps
 * those columns as the ledger's live SUM on every write, so re-deriving them per-request would duplicate
 * that invariant instead of relying on it. `points_to_next_level` is the one value genuinely derived at
 * read time, via `lib/levels.ts` (the same module T2.12c already uses for `current_level`).
 */
export async function GET(request: Request) {
  const result = await requireUser(request);
  if (isAuthFailure(result)) return result.response;
  const { user } = result;

  const { data: progress, error } = await supabaseAdmin
    .from("user")
    .select("total_points, current_level, trust_score")
    .eq("id", user.id)
    .single<ProgressRow>();

  if (error || !progress) {
    return NextResponse.json({ error: "Could not load progress" }, { status: 500 });
  }

  return NextResponse.json({
    total_points: progress.total_points,
    current_level: progress.current_level,
    points_to_next_level: pointsToNextLevel(progress.total_points),
    trust_score: progress.trust_score,
  });
}
