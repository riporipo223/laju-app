import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { isPremiumClub } from "@/lib/club-war/premium";
import { supabaseAdmin } from "@/lib/supabase";

interface JoinClubBody {
  invite_code?: unknown;
}

/** product-spec.md §4.24 AC22 — checked against the Circle OWNER's Premium status, never the joining
 * user's own (reuses `isPremiumClub`, the same "is this club's owner Premium" check §4.19's Club War
 * gate already established — currently a stub that always denies until T4.20 ships, so every Circle is
 * capped at the Free tier for now, which is the intended state, not a bug). */
const FREE_MEMBER_CAP = 20;
const PREMIUM_MEMBER_CAP = 100;

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

  const { count, error: countError } = await supabaseAdmin
    .from("club_member")
    .select("*", { count: "exact", head: true })
    .eq("club_id", club.id);
  if (countError) {
    return NextResponse.json({ error: "Could not check member count" }, { status: 500 });
  }
  const cap = (await isPremiumClub(club.id)) ? PREMIUM_MEMBER_CAP : FREE_MEMBER_CAP;
  if ((count ?? 0) >= cap) {
    // Never force-shrinks a Circle already over its cap (§4.24 AC24, freeze) — this only ever refuses
    // a NEW join, which is all this task enforces; the rest of AC24's freeze policy is separate work.
    return NextResponse.json({ error: "This Circle is full", code: "circle_full" }, { status: 409 });
  }

  const { error: insertError } = await supabaseAdmin
    .from("club_member")
    .insert({ user_id: user.id, club_id: club.id, role: "member" });
  if (insertError) {
    return NextResponse.json({ error: "Could not join club" }, { status: 500 });
  }

  // Opens this member's own membership stint — see `POST /api/clubs`'s identical write for why
  // (Circle Challenge's collective total needs it, schema migration has the full reasoning). Not
  // itself checked for an error, same posture as that other call site.
  await supabaseAdmin
    .from("club_membership_history")
    .insert({ club_id: club.id, user_id: user.id, joined_at: new Date().toISOString() });

  return NextResponse.json({ club_id: club.id, joined: true });
}
