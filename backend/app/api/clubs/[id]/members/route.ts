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

/**
 * T4.1b: self-leave only (v1 scope, 2026-09-25) — always the caller's own membership, no `:userId` in
 * the path (owner-removes-member is admin tooling, deferred behind T4.20b same as everything else
 * Premium-gated). 404 whether the caller was never a member of this club or the club id is bogus — same
 * "don't distinguish a non-match from a forbidden one" shape every delete-own-* route here uses.
 */
export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "club.leave");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  const { id } = await context.params;

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
