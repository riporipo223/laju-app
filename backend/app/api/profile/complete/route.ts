import { NextResponse } from "next/server";
import { isAuthFailure, requireAuthenticatedIdentity } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

interface ProfileCompleteBody {
  username?: unknown;
  display_name?: unknown;
  region_kecamatan?: unknown;
  region_kabupaten_kota?: unknown;
  region_provinsi?: unknown;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

/**
 * T2.4: database-api-spec.md §2.1. Uses `requireAuthenticatedIdentity`, not `requireUser` — this endpoint
 * is what CREATES the first `user` row for a newly-signed-up identity, so it cannot require one to already
 * exist (see lib/auth.ts's doc comment on the distinction).
 *
 * Region validation is presence-only (all 3 fields required, non-empty) — matching against a real
 * administrative catalog is explicitly out of scope for v1 (Scope: "Yang TIDAK dikerjakan").
 */
export async function POST(request: Request) {
  const identity = await requireAuthenticatedIdentity(request);
  if (isAuthFailure(identity)) return identity.response;

  let body: ProfileCompleteBody;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { username, display_name, region_kecamatan, region_kabupaten_kota, region_provinsi } = body;

  if (
    !isNonEmptyString(region_kecamatan) ||
    !isNonEmptyString(region_kabupaten_kota) ||
    !isNonEmptyString(region_provinsi)
  ) {
    return NextResponse.json(
      { error: "region_kecamatan, region_kabupaten_kota, and region_provinsi are all required" },
      { status: 400 }
    );
  }
  if (!isNonEmptyString(username)) {
    return NextResponse.json({ error: "username is required" }, { status: 400 });
  }

  const { data: userRow, error } = await supabaseAdmin
    .from("user")
    .upsert(
      {
        auth_user_id: identity.authUserId,
        username,
        display_name: isNonEmptyString(display_name) ? display_name : username,
        region_kecamatan,
        region_kabupaten_kota,
        region_provinsi,
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
