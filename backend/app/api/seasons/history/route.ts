import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

interface ResultRow {
  final_rank: number;
  final_points: number;
  league: string;
  participants: number;
  season: { id: string; name: string; start_at: string; end_at: string } | null;
}

/**
 * T3.8 (product-spec AC 4.7.3): the caller's final result in every season that has ended, newest first.
 *
 * Reads `season_result`, which is written once when a season ends (migration `20260922100000_season_results`) and never
 * updated — so a rank AND the league the season ended in survive later leaderboard rebuilds and league recalibration.
 * A user who was not on the board when a season closed (no counted points, or hidden by the trust filter) has no row for it.
 */
export async function GET(request: Request) {
  const result = await requireUser(request, "seasons.history");
  if (isAuthFailure(result)) return result.response;

  const { data, error } = await supabaseAdmin
    .from("season_result")
    .select("final_rank, final_points, league, participants, season:season_id (id, name, start_at, end_at)")
    .eq("user_id", result.user.id)
    .returns<ResultRow[]>();
  if (error) return NextResponse.json({ error: "Could not load season history" }, { status: 500 });

  const seasons = (data ?? [])
    .filter((row): row is ResultRow & { season: NonNullable<ResultRow["season"]> } => row.season !== null)
    .sort((a, b) => Date.parse(b.season.end_at) - Date.parse(a.season.end_at))
    .map((row) => ({
      season_id: row.season.id,
      name: row.season.name,
      start_at: row.season.start_at,
      end_at: row.season.end_at,
      final_rank: row.final_rank,
      final_points: row.final_points,
      league: row.league,
      participants: row.participants,
    }));

  return NextResponse.json({ seasons });
}
