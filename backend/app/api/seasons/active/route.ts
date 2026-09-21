import { NextResponse } from "next/server";
import { isAuthFailure, requireAuthenticatedIdentity } from "@/lib/auth";
import { leagueFor } from "@/lib/season-league";
import { supabaseAdmin } from "@/lib/supabase";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

interface SeasonRow {
  id: string;
  name: string;
  start_at: string;
  end_at: string;
  status: string;
}

async function loadMe(authUserId: string, seasonId: string) {
  const { data: userRow } = await supabaseAdmin
    .from("user")
    .select("id")
    .eq("auth_user_id", authUserId)
    .is("deleted_at", null)
    .maybeSingle<{ id: string }>();
  if (!userRow) return null;
  const { data: points, error } = await supabaseAdmin.rpc("season_points", { p_user: userRow.id, p_season: seasonId });
  if (error || typeof points !== "number") return null;
  return { season_points: points, league: leagueFor(points) };
}

/**
 * T2.17: database-api-spec.md §2.5. Response is identical for every caller (no user-specific data), but
 * still requires a valid Supabase JWT per the spec's general "Requests without a valid Supabase JWT →
 * 401" rule — uses `requireAuthenticatedIdentity` (not the heavier `requireUser`) since no `user` row
 * lookup is needed to build this response.
 *
 * Season lifecycle transitions live in T3.6 (`transition_season` / `advance_seasons`) — this only reads whichever row has
 * `status='active'`.
 *
 * T3.7a adds the additive `me: { season_points, league } | null`. It is derived from the ledger on every call (never
 * stored) via `season_points()`, the same quantity as `leaderboard_entry.points`. `me` is null — not an error — when the
 * caller has no profile yet or the points read fails: the season itself is still valid, and clients ignore unknown fields.
 */
export async function GET(request: Request) {
  const identity = await requireAuthenticatedIdentity(request, "seasons.active");
  if (isAuthFailure(identity)) return identity.response;

  const { data: season, error } = await supabaseAdmin
    .from("season")
    .select("id, name, start_at, end_at, status")
    .eq("status", "active")
    .maybeSingle<SeasonRow>();

  if (error) {
    return NextResponse.json({ error: "Could not load active season" }, { status: 500 });
  }
  if (!season) {
    return NextResponse.json({ error: "No active season" }, { status: 404 });
  }

  const daysRemaining = Math.max(0, Math.ceil((new Date(season.end_at).getTime() - Date.now()) / MS_PER_DAY));

  return NextResponse.json({
    me: await loadMe(identity.authUserId, season.id),
    id: season.id,
    name: season.name,
    start_at: season.start_at,
    end_at: season.end_at,
    status: season.status,
    days_remaining: daysRemaining,
  });
}
