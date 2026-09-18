import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const REGION_SCOPES = ["kecamatan", "kabupaten_kota", "provinsi"];

interface EntryRow {
  rank: number;
  user_id: string;
  frozen_display_name: string | null;
  points: number;
}

interface ScopeRow {
  computed_at: string;
  insufficient_data: boolean;
}

function badRequest(message: string) {
  return NextResponse.json({ error: message }, { status: 400 });
}

/**
 * T2.19: database-api-spec.md §2.4, `scope=global` only (region scopes are T3.4). Reads the precomputed
 * `leaderboard_entry` / `leaderboard_scope` rows written by T2.18's pg_cron job — never aggregates
 * `point_transaction` live (architecture.md §4).
 *
 * Low-trust users are already absent from those rows (the rebuild filters `trust_score`, see migration
 * `leaderboard_hide_low_trust`), so `entries`, `me.rank` and `user_count` agree without any read-time
 * filtering here. `me` is `null` when the caller is not on the board (no counted points yet, or hidden).
 */
export async function GET(request: Request) {
  const result = await requireUser(request);
  if (isAuthFailure(result)) return result.response;
  const { user } = result;

  const params = new URL(request.url).searchParams;

  const scope = params.get("scope");
  if (scope === null) return badRequest("scope is required");
  if (REGION_SCOPES.includes(scope)) return badRequest(`scope=${scope} is not supported yet`);
  if (scope !== "global") return badRequest("scope must be one of: global, kecamatan, kabupaten_kota, provinsi");

  const limitParam = params.get("limit");
  let limit = DEFAULT_LIMIT;
  if (limitParam !== null) {
    limit = Number(limitParam);
    if (!Number.isInteger(limit) || limit < 1 || limit > MAX_LIMIT) {
      return badRequest(`limit must be an integer between 1 and ${MAX_LIMIT}`);
    }
  }

  let seasonId = params.get("season_id");
  if (seasonId !== null && !UUID_PATTERN.test(seasonId)) return badRequest("season_id must be a valid UUID");
  if (seasonId === null) {
    const { data: season, error } = await supabaseAdmin
      .from("season")
      .select("id")
      .eq("status", "active")
      .maybeSingle<{ id: string }>();
    if (error) return NextResponse.json({ error: "Could not load season" }, { status: 500 });
    if (!season) return NextResponse.json({ error: "No active season" }, { status: 404 });
    seasonId = season.id;
  }

  const [scopeResult, entriesResult, meResult] = await Promise.all([
    supabaseAdmin
      .from("leaderboard_scope")
      .select("computed_at, insufficient_data")
      .eq("season_id", seasonId)
      .eq("scope_type", "global")
      .eq("scope_id", "GLOBAL")
      .maybeSingle<ScopeRow>(),
    supabaseAdmin
      .from("leaderboard_entry")
      .select("rank, user_id, frozen_display_name, points")
      .eq("season_id", seasonId)
      .eq("scope_type", "global")
      .eq("scope_id", "GLOBAL")
      .order("points", { ascending: false })
      .order("user_id", { ascending: true })
      .limit(limit),
    supabaseAdmin
      .from("leaderboard_entry")
      .select("rank, points")
      .eq("season_id", seasonId)
      .eq("scope_type", "global")
      .eq("scope_id", "GLOBAL")
      .eq("user_id", user.id)
      .maybeSingle<{ rank: number; points: number }>(),
  ]);

  if (scopeResult.error || entriesResult.error || meResult.error) {
    return NextResponse.json({ error: "Could not load leaderboard" }, { status: 500 });
  }

  const entries = (entriesResult.data ?? []) as EntryRow[];
  return NextResponse.json({
    season_id: seasonId,
    scope: "global",
    scope_id: null,
    computed_at: scopeResult.data?.computed_at ?? null,
    insufficient_data: scopeResult.data?.insufficient_data ?? false,
    entries: entries.map((row) => ({
      rank: row.rank,
      user_id: row.user_id,
      username: row.frozen_display_name,
      points: row.points,
    })),
    me: meResult.data ? { rank: meResult.data.rank, points: meResult.data.points } : null,
  });
}
