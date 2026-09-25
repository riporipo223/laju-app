import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { isPremiumUser } from "@/lib/club/premium";
import { supabaseAdmin } from "@/lib/supabase";

const MAX_NAME_LENGTH = 60;
const MAX_DESCRIPTION_LENGTH = 500;
const INVITE_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I/l — avoids misreads
const INVITE_CODE_LENGTH = 8;

/** T4.1a (20260925150000_club_extend_and_premium_gate.sql): must match the DB CHECK constraint. */
const VALID_PRIVACY = ["public", "invite_only"] as const;

function generateInviteCode(): string {
  let code = "";
  for (let i = 0; i < INVITE_CODE_LENGTH; i++) {
    code += INVITE_CODE_ALPHABET[Math.floor(Math.random() * INVITE_CODE_ALPHABET.length)];
  }
  return code;
}

interface CreateClubBody {
  name?: unknown;
  description?: unknown;
  privacy?: unknown;
}

/**
 * T4.1 (phase-4-backlog.md §4.24 AC1-AC21, reversed 2026-09-25 — see the migration's own scope note):
 * creating a club requires Premium. Until T4.20 ships, `isPremiumUser` always denies
 * (`lib/club/premium.ts`), so this answers 403 `not_premium` for every caller — by design, same shape
 * as `POST /api/club-wars` and its `isPremiumClub` stub.
 *
 * One-club-per-user is enforced at the DB level by `club_member.user_id`'s primary key (T4.2a) — the
 * membership lookup below is only for a clean error message before the insert, not the actual
 * invariant.
 */
export async function POST(request: Request) {
  const auth = await requireUser(request, "club.create");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  let body: CreateClubBody;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { name, description, privacy } = body;
  if (typeof name !== "string" || name.trim().length === 0) {
    return NextResponse.json({ error: "name is required" }, { status: 400 });
  }
  const trimmedName = name.trim();
  if (trimmedName.length > MAX_NAME_LENGTH) {
    return NextResponse.json({ error: `name may be at most ${MAX_NAME_LENGTH} characters` }, { status: 400 });
  }
  if (description !== undefined && description !== null && typeof description !== "string") {
    return NextResponse.json({ error: "description must be a string" }, { status: 400 });
  }
  const trimmedDescription = typeof description === "string" ? description.trim() : null;
  if (trimmedDescription && trimmedDescription.length > MAX_DESCRIPTION_LENGTH) {
    return NextResponse.json({ error: `description may be at most ${MAX_DESCRIPTION_LENGTH} characters` }, { status: 400 });
  }
  const resolvedPrivacy = privacy ?? "public";
  if (!VALID_PRIVACY.includes(resolvedPrivacy as (typeof VALID_PRIVACY)[number])) {
    return NextResponse.json({ error: `privacy must be one of: ${VALID_PRIVACY.join(", ")}` }, { status: 400 });
  }

  const premium = await isPremiumUser(user.id);
  if (!premium) {
    return NextResponse.json({ error: "Creating a club requires Premium", code: "not_premium" }, { status: 403 });
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

  const inviteCode = resolvedPrivacy === "invite_only" ? generateInviteCode() : null;

  const { data: club, error: clubError } = await supabaseAdmin
    .from("club")
    .insert({
      name: trimmedName,
      description: trimmedDescription || null,
      privacy: resolvedPrivacy,
      invite_code: inviteCode,
    })
    .select("id, name, description, privacy, invite_code, created_at")
    .single<{
      id: string;
      name: string;
      description: string | null;
      privacy: string;
      invite_code: string | null;
      created_at: string;
    }>();
  if (clubError || !club) {
    return NextResponse.json({ error: "Could not create club" }, { status: 500 });
  }

  const { error: memberError } = await supabaseAdmin
    .from("club_member")
    .insert({ user_id: user.id, club_id: club.id, role: "owner" });
  if (memberError) {
    return NextResponse.json({ error: "Club created but membership could not be saved" }, { status: 500 });
  }

  return NextResponse.json(
    {
      club_id: club.id,
      name: club.name,
      description: club.description,
      privacy: club.privacy,
      invite_code: club.invite_code,
      created_at: club.created_at,
    },
    { status: 201 }
  );
}
