import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { computeClubAnalytics } from "@/lib/club-analytics";
import { isPremiumClub } from "@/lib/club-war/premium";
import { MIN_DISTANCE_KM_FOR_POINTS } from "@/lib/point-calculation";
import { supabaseAdmin } from "@/lib/supabase";

const QUALIFYING_RUN_STATUSES = ["validated", "approved", "flagged"] as const;
const TOP_CONTRIBUTORS_COUNT = 5;
const ROLLING_WINDOW_DAYS = 30;

/**
 * T4.1 (product-spec.md §4.24 AC12): Circle admin analytics — aggregate distance/points, active
 * member count, top-5 contributors, rolling 30 days. Gated on caller owner/admin AND the Circle
 * being a Premium Club (AC11/AC24 freeze — reuses `isPremiumClub`, same `not_premium_club` shape
 * `POST /api/club-wars` and this feature's own challenge-create route use).
 *
 * "Active member" reuses §4.20 Club Aktif's exact definition (AC12: "the same 'ran' definition and
 * live roster... reused, not a new metric") — a qualifying run (`validated`/`approved`/`flagged`,
 * clearing the ADR-0009 distance gate) inside the window. Unlike Circle Challenge, this is CURRENT
 * members only — no membership-history/departed-member carry-forward, since analytics is a live
 * snapshot of the roster right now, not a running collective total.
 */
export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "club.analytics.get");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  const { id } = await context.params;

  const { data: callerMembership, error: roleLookupError } = await supabaseAdmin
    .from("club_member")
    .select("role")
    .eq("user_id", user.id)
    .eq("club_id", id)
    .maybeSingle<{ role: string }>();
  if (roleLookupError) {
    return NextResponse.json({ error: "Could not check caller's role" }, { status: 500 });
  }
  if (!callerMembership || (callerMembership.role !== "owner" && callerMembership.role !== "admin")) {
    return NextResponse.json({ error: "Only an owner or admin can view analytics" }, { status: 403 });
  }

  if (!(await isPremiumClub(id))) {
    return NextResponse.json({ error: "not_premium_club" }, { status: 403 });
  }

  const { data: memberRows, error: memberError } = await supabaseAdmin
    .from("club_member")
    .select("user_id")
    .eq("club_id", id)
    .order("user_id", { ascending: true });
  if (memberError) {
    return NextResponse.json({ error: "Could not load members" }, { status: 500 });
  }
  const memberIds = (memberRows ?? []).map((row: { user_id: string }) => row.user_id);

  if (memberIds.length === 0) {
    return NextResponse.json({ total_distance_meters: 0, total_points: 0, active_member_count: 0, top_contributors: [] });
  }

  const windowStart = new Date(Date.now() - ROLLING_WINDOW_DAYS * 24 * 60 * 60 * 1000);
  const { data: runRows, error: runError } = await supabaseAdmin
    .from("run")
    .select("user_id, distance_meters, final_points_awarded")
    .in("user_id", memberIds)
    .in("status", QUALIFYING_RUN_STATUSES)
    .gte("distance_meters", MIN_DISTANCE_KM_FOR_POINTS * 1000)
    .gte("started_at", windowStart.toISOString())
    .order("started_at", { ascending: true });
  if (runError) {
    return NextResponse.json({ error: "Could not load runs" }, { status: 500 });
  }

  const analytics = computeClubAnalytics({
    runs: (runRows ?? []).map((row: { user_id: string; distance_meters: number; final_points_awarded: number | null }) => ({
      userId: row.user_id,
      distanceMeters: row.distance_meters,
      finalPointsAwarded: row.final_points_awarded,
    })),
    topN: TOP_CONTRIBUTORS_COUNT,
  });

  return NextResponse.json({
    total_distance_meters: analytics.totalDistanceMeters,
    total_points: analytics.totalPoints,
    active_member_count: analytics.activeMemberCount,
    top_contributors: analytics.topContributors.map((entry) => ({
      user_id: entry.userId,
      distance_meters: entry.distanceMeters,
      points: entry.points,
    })),
  });
}
