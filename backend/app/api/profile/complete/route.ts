import { NextResponse } from "next/server";
import { isAuthFailure, requireAuthenticatedIdentity } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

interface ProfileCompleteBody {
  username?: unknown;
  display_name?: unknown;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

/**
 * T2.4: database-api-spec.md §2.1. Uses `requireAuthenticatedIdentity`, not `requireUser` — this endpoint
 * is what CREATES the first `user` row for a newly-signed-up identity, so it cannot require one to already
 * exist (see lib/auth.ts's doc comment on the distinction).
 *
 * Region validation was removed 2026-09-22 (D1 reversed — product-spec.md §4.1; Local Leaderboard,
 * the only consumer region data was ever collected for, was cancelled permanently, §4.6). The
 * `region_*` columns were physically dropped from `user` by migration 20260923090000 (applied
 * 2026-09-23); this endpoint stopped reading/writing them the day before, as the EXPAND half of
 * expand→migrate→verify→contract.
 */
export async function POST(request: Request) {
  const identity = await requireAuthenticatedIdentity(request, "profile.complete");
  if (isAuthFailure(identity)) return identity.response;

  let body: ProfileCompleteBody;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { username, display_name } = body;

  // Region validation removed 2026-09-22 (D1 reversed, product-spec.md §4.1): region is no longer
  // collected at all, so there is nothing to validate. Any `region_*` keys a not-yet-updated client
  // still sends are simply ignored rather than rejected — that tolerance is deliberate, so an older
  // app build keeps working through the rollout window instead of breaking on a 400.
  if (!isNonEmptyString(username)) {
    return NextResponse.json({ error: "username is required" }, { status: 400 });
  }

  // database-api-spec.md §2.1b point 3 / §3: a JWT stays cryptographically valid after account deletion until
  // it expires, and this route (unlike every other) does not go through `requireUser`'s `deleted_at` check.
  // Without this guard a still-valid token could re-populate the just-anonymized username/region — silently
  // undoing the deletion (Round 7 finding B7-10).
  const { data: existing, error: existingError } = await supabaseAdmin
    .from("user")
    .select("deleted_at")
    .eq("auth_user_id", identity.authUserId)
    .maybeSingle<{ deleted_at: string | null }>();
  if (existingError) {
    return NextResponse.json({ error: "Could not save profile" }, { status: 500 });
  }
  if (existing && existing.deleted_at !== null) {
    return NextResponse.json({ error: "This account has been deleted" }, { status: 401 });
  }

  const { data: userRow, error } = await supabaseAdmin
    .from("user")
    .upsert(
      {
        auth_user_id: identity.authUserId,
        username,
        display_name: isNonEmptyString(display_name) ? display_name : username,
      },
      { onConflict: "auth_user_id" }
    )
    .select("id, username, total_points, current_level")
    .single();

  if (error || !userRow) {
    return NextResponse.json({ error: "Could not save profile" }, { status: 500 });
  }

  return NextResponse.json(
    {
      id: userRow.id,
      username: userRow.username,
      total_points: userRow.total_points,
      current_level: userRow.current_level,
    },
    { status: 201 }
  );
}
