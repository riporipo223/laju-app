import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { computeChallengeProgress, computeChallengeStatus } from "@/lib/club-challenge";
import { isPremiumClub } from "@/lib/club-war/premium";
import { MIN_DISTANCE_KM_FOR_POINTS } from "@/lib/point-calculation";
import { supabaseAdmin } from "@/lib/supabase";

const QUALIFYING_RUN_STATUSES = ["validated", "approved", "flagged"] as const;

const MAX_NAME_LENGTH = 100;
const VALID_TARGET_TYPES = ["distance", "duration"] as const;
const OPEN_STATUSES = ["active", "target_reached"] as const;

interface CreateChallengeBody {
  name?: unknown;
  target_type?: unknown;
  target_value?: unknown;
  deadline?: unknown;
}

/**
 * T4.1 (product-spec.md §4.24 AC13, mechanics decided 2026-09-26): create a Circle Challenge. Gated
 * on caller owner/admin AND the Circle being a Premium Club (§4.24 AC11/AC24 freeze — reuses
 * `isPremiumClub`, the same check `POST /api/club-wars` uses, same `not_premium_club` response
 * shape, never a new Premium-check mechanism). At most one OPEN challenge per club at a time — the
 * schema's own partial unique index (`club_challenge_one_open_per_club_idx`) is the real backstop;
 * this route's own SELECT is only for a clean 409 instead of a raw constraint-violation 500.
 */
export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "club.challenge.create");
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
    return NextResponse.json({ error: "Only an owner or admin can create a challenge" }, { status: 403 });
  }

  if (!(await isPremiumClub(id))) {
    return NextResponse.json({ error: "not_premium_club" }, { status: 403 });
  }

  let body: CreateChallengeBody = {};
  try {
    body = (await request.json()) as CreateChallengeBody;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { name, target_type: targetType, target_value: targetValue, deadline } = body;
  if (typeof name !== "string" || name.trim().length === 0) {
    return NextResponse.json({ error: "name is required" }, { status: 400 });
  }
  const trimmedName = name.trim();
  if (trimmedName.length > MAX_NAME_LENGTH) {
    return NextResponse.json({ error: `name may be at most ${MAX_NAME_LENGTH} characters` }, { status: 400 });
  }
  if (!VALID_TARGET_TYPES.includes(targetType as (typeof VALID_TARGET_TYPES)[number])) {
    return NextResponse.json({ error: `target_type must be one of: ${VALID_TARGET_TYPES.join(", ")}` }, { status: 400 });
  }
  if (typeof targetValue !== "number" || !Number.isFinite(targetValue) || targetValue <= 0) {
    return NextResponse.json({ error: "target_value must be a positive number" }, { status: 400 });
  }
  const deadlineDate = typeof deadline === "string" ? new Date(deadline) : null;
  if (!deadlineDate || Number.isNaN(deadlineDate.getTime())) {
    return NextResponse.json({ error: "deadline must be a valid ISO 8601 timestamp" }, { status: 400 });
  }
  if (deadlineDate.getTime() <= Date.now()) {
    return NextResponse.json({ error: "deadline must be in the future" }, { status: 400 });
  }

  const { data: existing, error: existingLookupError } = await supabaseAdmin
    .from("club_challenge")
    .select("id")
    .eq("club_id", id)
    .in("status", OPEN_STATUSES)
    .maybeSingle<{ id: string }>();
  if (existingLookupError) {
    return NextResponse.json({ error: "Could not check for an existing challenge" }, { status: 500 });
  }
  if (existing) {
    return NextResponse.json(
      { error: "This Circle already has an active challenge", code: "challenge_active" },
      { status: 409 }
    );
  }

  const { data: challenge, error: insertError } = await supabaseAdmin
    .from("club_challenge")
    .insert({
      club_id: id,
      name: trimmedName,
      target_type: targetType,
      target_value: targetValue,
      deadline: deadlineDate.toISOString(),
    })
    .select("id, club_id, name, target_type, target_value, deadline, status, created_at")
    .single<{
      id: string;
      club_id: string;
      name: string;
      target_type: string;
      target_value: number;
      deadline: string;
      status: string;
      created_at: string;
    }>();
  if (insertError || !challenge) {
    return NextResponse.json({ error: "Could not create challenge" }, { status: 500 });
  }

  return NextResponse.json(
    {
      challenge_id: challenge.id,
      club_id: challenge.club_id,
      name: challenge.name,
      target_type: challenge.target_type,
      target_value: challenge.target_value,
      deadline: challenge.deadline,
      status: challenge.status,
      created_at: challenge.created_at,
    },
    { status: 201 }
  );
}

/**
 * T4.1 (product-spec.md §4.24 AC13): a Circle's current (or most recently closed/cancelled)
 * challenge — progress, individual ranking, and status. Visible to any current member, not just
 * owner/admin (unlike creating a challenge or viewing analytics) — AC14. Not Premium-gated either:
 * AC24's freeze only locks STARTING a new challenge and viewing analytics, never reading an
 * already-created challenge, so a Circle whose owner's Premium has since lapsed still shows its
 * existing challenge exactly as before.
 *
 * Status is computed live every read (`computeChallengeStatus`, never early-closed per AC13) and
 * written back to the row when it changes, so it becomes a fast, consistent read on the next call —
 * a failed write here doesn't affect what's returned, only what's cached in the row.
 */
export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "club.challenge.get");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  const { id } = await context.params;

  const { data: callerMembership, error: membershipError } = await supabaseAdmin
    .from("club_member")
    .select("user_id")
    .eq("user_id", user.id)
    .eq("club_id", id)
    .maybeSingle<{ user_id: string }>();
  if (membershipError) {
    return NextResponse.json({ error: "Could not check membership" }, { status: 500 });
  }
  if (!callerMembership) {
    return NextResponse.json({ error: "Only Circle members can view its challenge" }, { status: 403 });
  }

  const { data: challengeRows, error: challengeError } = await supabaseAdmin
    .from("club_challenge")
    .select("id, club_id, name, target_type, target_value, deadline, status, created_at")
    .eq("club_id", id)
    .order("created_at", { ascending: false })
    .limit(1);
  if (challengeError) {
    return NextResponse.json({ error: "Could not load challenge" }, { status: 500 });
  }
  const challenge = challengeRows?.[0] as
    | {
        id: string;
        club_id: string;
        name: string;
        target_type: "distance" | "duration";
        target_value: number;
        deadline: string;
        status: string;
        created_at: string;
      }
    | undefined;
  if (!challenge) {
    return NextResponse.json({ error: "This Circle has no challenge" }, { status: 404 });
  }

  const { data: historyRows, error: historyError } = await supabaseAdmin
    .from("club_membership_history")
    .select("user_id, joined_at, left_at")
    .eq("club_id", id);
  if (historyError) {
    return NextResponse.json({ error: "Could not load membership history" }, { status: 500 });
  }

  const { data: currentMemberRows, error: currentMemberError } = await supabaseAdmin
    .from("club_member")
    .select("user_id")
    .eq("club_id", id)
    .order("user_id", { ascending: true });
  if (currentMemberError) {
    return NextResponse.json({ error: "Could not load current members" }, { status: 500 });
  }

  const historyUserIds = [...new Set((historyRows ?? []).map((row: { user_id: string }) => row.user_id))];
  const now = new Date();
  const deadline = new Date(challenge.deadline);
  const windowEnd = now.getTime() < deadline.getTime() ? now : deadline;

  let runRows: { user_id: string; started_at: string; distance_meters: number; duration_seconds: number }[] = [];
  if (historyUserIds.length > 0) {
    const { data, error: runError } = await supabaseAdmin
      .from("run")
      .select("user_id, started_at, distance_meters, duration_seconds")
      .in("user_id", historyUserIds)
      .in("status", QUALIFYING_RUN_STATUSES)
      .gte("distance_meters", MIN_DISTANCE_KM_FOR_POINTS * 1000)
      .gte("started_at", challenge.created_at)
      .lte("started_at", windowEnd.toISOString());
    if (runError) {
      return NextResponse.json({ error: "Could not load qualifying runs" }, { status: 500 });
    }
    runRows = data ?? [];
  }

  const progress = computeChallengeProgress({
    targetType: challenge.target_type,
    history: (historyRows ?? []).map((row: { user_id: string; joined_at: string; left_at: string | null }) => ({
      userId: row.user_id,
      joinedAt: new Date(row.joined_at),
      leftAt: row.left_at ? new Date(row.left_at) : null,
    })),
    currentMemberIds: new Set((currentMemberRows ?? []).map((row: { user_id: string }) => row.user_id)),
    runs: runRows.map((row) => ({
      userId: row.user_id,
      startedAt: new Date(row.started_at),
      distanceMeters: row.distance_meters,
      durationSeconds: row.duration_seconds,
    })),
  });

  const status = computeChallengeStatus({
    storedStatus: challenge.status,
    deadline,
    targetValue: challenge.target_value,
    collectiveTotal: progress.collectiveTotal,
    now,
  });

  if (status !== challenge.status) {
    await supabaseAdmin.from("club_challenge").update({ status }).eq("id", challenge.id);
  }

  return NextResponse.json({
    challenge_id: challenge.id,
    club_id: challenge.club_id,
    name: challenge.name,
    target_type: challenge.target_type,
    target_value: challenge.target_value,
    deadline: challenge.deadline,
    status,
    collective_total: progress.collectiveTotal,
    ranking: progress.ranking.map((entry) => ({ user_id: entry.userId, total: entry.total })),
  });
}
