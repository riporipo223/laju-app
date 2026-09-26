import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

const OPEN_STATUSES = ["active", "target_reached"] as const;

/**
 * T4.1 (product-spec.md §4.24 AC13): owner cancels the Circle's currently open challenge — "full,
 * centralized owner control," OWNER ONLY, not admin (AC13's own wording, unlike every other Circle
 * governance action AC23 makes free-for-owner-AND-admin). Freezes the ranking as a final historical
 * record: sets `status = 'cancelled'`, never deletes the row — `GET /api/clubs/[id]/challenge` still
 * returns it afterward with whatever ranking had accumulated at the moment of cancellation.
 *
 * BLOCKED, not built: AC13 also calls for a real push notification to every participant on cancel.
 * Checked this session (grepped `backend/` and `ios/` for APNs/PushKit/device-token/
 * UNUserNotificationCenter registration): this codebase has ZERO remote push infrastructure — only
 * local, client-scheduled notifications exist (`ios/Laju/ViewModels/NotificationScheduling.swift`,
 * T1.16 streak reminders), which cannot be triggered from the server. Building APNs device-token
 * registration + delivery is a separate, much larger infrastructure task, out of scope here. The
 * ranking-freeze half of this requirement is fully built; the push half is not.
 */
export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "club.challenge.cancel");
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
  if (!callerMembership || callerMembership.role !== "owner") {
    return NextResponse.json({ error: "Only the owner can cancel a challenge" }, { status: 403 });
  }

  const { data: openChallenge, error: openLookupError } = await supabaseAdmin
    .from("club_challenge")
    .select("id")
    .eq("club_id", id)
    .in("status", OPEN_STATUSES)
    .maybeSingle<{ id: string }>();
  if (openLookupError) {
    return NextResponse.json({ error: "Could not check for an open challenge" }, { status: 500 });
  }
  if (!openChallenge) {
    return NextResponse.json({ error: "This Circle has no open challenge to cancel" }, { status: 404 });
  }

  const { error: updateError } = await supabaseAdmin
    .from("club_challenge")
    .update({ status: "cancelled", cancelled_at: new Date().toISOString() })
    .eq("id", openChallenge.id);
  if (updateError) {
    return NextResponse.json({ error: "Could not cancel challenge" }, { status: 500 });
  }

  return NextResponse.json({ challenge_id: openChallenge.id, cancelled: true });
}
