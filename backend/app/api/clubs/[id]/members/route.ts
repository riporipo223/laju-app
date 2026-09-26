import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

interface MemberRow {
  user_id: string;
  role: string;
  joined_at: string;
  user: { username: string | null; display_name: string | null; avatar_url: string | null } | null;
}

/**
 * T4.1b (phase-4-backlog.md, v1 scoping session 2026-09-25): a club's member list, joined-oldest-first
 * (owner first, since they joined at club creation). Visible to any authenticated caller, not just the
 * club's own members — same posture the public feed uses, no membership check before reading.
 */
export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "club.members");
  if (isAuthFailure(auth)) return auth.response;

  const { id } = await context.params;

  const { data, error } = await supabaseAdmin
    .from("club_member")
    .select("user_id, role, joined_at, user:user_id(username, display_name, avatar_url)")
    .eq("club_id", id)
    .order("joined_at", { ascending: true });
  if (error) {
    return NextResponse.json({ error: "Could not load members" }, { status: 500 });
  }

  const rows = (data ?? []) as unknown as MemberRow[];
  return NextResponse.json({
    members: rows.map((row) => ({
      user_id: row.user_id,
      username: row.user?.username ?? null,
      display_name: row.user?.display_name ?? null,
      avatar_url: row.user?.avatar_url ?? null,
      role: row.role,
      joined_at: row.joined_at,
    })),
  });
}

interface DeleteMemberBody {
  user_id?: unknown;
}

/**
 * T4.1b/T4.1c (self-leave, 2026-09-25) + kick-member (product-spec.md §4.24 AC23, added 2026-09-26,
 * HANDOFF.md "Audit drift 2026-09-26" item 4): no `user_id` in the body is self-leave, unchanged from
 * the original v1 scope — always the caller's own membership, 404 whether the caller was never a
 * member of this club or the club id is bogus (same "don't distinguish a non-match from a forbidden
 * one" shape every delete-own-* route here uses).
 *
 * A `user_id` in the body targeting someone else is kick-member — gated ONLY on "caller is owner or
 * admin of this club," never Premium (AC23 is explicit: kick-member is free for every tier, unlike the
 * Premium-gated admin tools AC11-AC13; a prior version of this comment wrongly bundled the two, now
 * corrected). A `user_id` equal to the caller's own is rejected outright, not silently treated as
 * self-leave — an owner can't leave this way at all (AC16: transfer ownership or archive first), and a
 * non-owner kicking themselves has the plain self-leave path already, so this shape has no valid use.
 *
 * The target's own role is also checked before deleting: kicking a target whose role is `owner` is
 * rejected the same way — an owner can only leave via AC16's transfer/archive path, never by someone
 * else kicking them. (Fixed 2026-09-26: an earlier version of this endpoint had no such check, so an
 * admin could kick the club's owner, leaving the Circle with no owner at all — a real data-corruption
 * gap the prior audit session found and flagged rather than guessed a fix for; see
 * phase-4-backlog.md T4.1b for the full note.)
 */
export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "club.leave");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  const { id } = await context.params;

  let body: DeleteMemberBody = {};
  try {
    body = (await request.json()) as DeleteMemberBody;
  } catch {
    body = {};
  }
  const targetUserId = typeof body.user_id === "string" && body.user_id.length > 0 ? body.user_id : null;

  if (targetUserId === null) {
    const { data, error } = await supabaseAdmin
      .from("club_member")
      .delete()
      .eq("user_id", user.id)
      .eq("club_id", id)
      .select("club_id")
      .maybeSingle<{ club_id: string }>();
    if (error) {
      return NextResponse.json({ error: "Could not leave club" }, { status: 500 });
    }
    if (!data) {
      return NextResponse.json({ error: "You are not a member of this club" }, { status: 404 });
    }
    return NextResponse.json({ club_id: data.club_id, left: true });
  }

  if (targetUserId === user.id) {
    return NextResponse.json(
      { error: "Use the plain leave request (no user_id) to remove yourself" },
      { status: 400 }
    );
  }

  const { data: callerMembership, error: callerLookupError } = await supabaseAdmin
    .from("club_member")
    .select("role")
    .eq("user_id", user.id)
    .eq("club_id", id)
    .maybeSingle<{ role: string }>();
  if (callerLookupError) {
    return NextResponse.json({ error: "Could not check caller's role" }, { status: 500 });
  }
  if (!callerMembership || (callerMembership.role !== "owner" && callerMembership.role !== "admin")) {
    return NextResponse.json({ error: "Only an owner or admin can remove another member" }, { status: 403 });
  }

  const { data: targetMembership, error: targetLookupError } = await supabaseAdmin
    .from("club_member")
    .select("role")
    .eq("user_id", targetUserId)
    .eq("club_id", id)
    .maybeSingle<{ role: string }>();
  if (targetLookupError) {
    return NextResponse.json({ error: "Could not check target's role" }, { status: 500 });
  }
  if (targetMembership?.role === "owner") {
    return NextResponse.json(
      { error: "The owner can't be kicked — transfer ownership or archive the Circle first (AC16)" },
      { status: 400 }
    );
  }

  const { data, error } = await supabaseAdmin
    .from("club_member")
    .delete()
    .eq("user_id", targetUserId)
    .eq("club_id", id)
    .select("club_id")
    .maybeSingle<{ club_id: string }>();
  if (error) {
    return NextResponse.json({ error: "Could not remove member" }, { status: 500 });
  }
  if (!data) {
    return NextResponse.json({ error: "That user is not a member of this club" }, { status: 404 });
  }

  return NextResponse.json({ club_id: data.club_id, kicked_user_id: targetUserId, kicked: true });
}
