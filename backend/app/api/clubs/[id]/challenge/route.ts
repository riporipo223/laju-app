import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { isPremiumClub } from "@/lib/club-war/premium";
import { supabaseAdmin } from "@/lib/supabase";

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
