import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

interface JoinClubBody {
  invite_code?: unknown;
}

/**
 * T4.1b (phase-4-backlog.md, v1 scoping session 2026-09-25): join a club. `public` clubs need no invite
 * code — direct join, no request/approval (2026-09-23 scoping). `invite_only` clubs need the matching
 * `invite_code`, compared case-insensitively (v1 decision) — the code is regenerable text, not a DB
 * enum, chosen precisely so it's easy to say over voice/text without worrying about case.
 *
 * One-club-per-user is the same PK invariant `POST /api/clubs` relies on (`club_member.user_id`) — the
 * membership lookup here is only for a clean error message, not the actual backstop.
 */
export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "club.join");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  const { id } = await context.params;

  let body: JoinClubBody = {};
  try {
    body = (await request.json()) as JoinClubBody;
  } catch {
    body = {};
  }
  const { invite_code } = body;
  if (invite_code !== undefined && invite_code !== null && typeof invite_code !== "string") {
    return NextResponse.json({ error: "invite_code must be a string" }, { status: 400 });
  }

  const { data: club, error: clubError } = await supabaseAdmin
    .from("club")
    .select("id, privacy, invite_code")
    .eq("id", id)
    .maybeSingle<{ id: string; privacy: string; invite_code: string | null }>();
  if (clubError) {
    return NextResponse.json({ error: "Could not look up club" }, { status: 500 });
  }
  if (!club) {
    return NextResponse.json({ error: "Club not found" }, { status: 404 });
  }

  const { data: existingMembership, error: membershipLookupError } = await supabaseAdmin
    .from("club_member")
    .select("club_id")
    .eq("user_id", user.id)
    .maybeSingle<{ club_id: string }>();
  if (membershipLookupError) {
    return NextResponse.json({ error: "Could not check existing membership" }, { status: 500 });
  }
  if (existingMembership) {
    return NextResponse.json({ error: "You are already in a club" }, { status: 409 });
  }

  if (club.privacy === "invite_only") {
    const providedCode = typeof invite_code === "string" ? invite_code.trim().toUpperCase() : null;
    const requiredCode = club.invite_code?.toUpperCase() ?? null;
    if (!providedCode || !requiredCode || providedCode !== requiredCode) {
      return NextResponse.json({ error: "Invalid or missing invite code" }, { status: 403 });
    }
  }

  const { error: insertError } = await supabaseAdmin
    .from("club_member")
    .insert({ user_id: user.id, club_id: club.id, role: "member" });
  if (insertError) {
    return NextResponse.json({ error: "Could not join club" }, { status: 500 });
  }

  return NextResponse.json({ club_id: club.id, joined: true });
}
