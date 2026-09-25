import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { isPremiumUser } from "@/lib/club/premium";
import { supabaseAdmin } from "@/lib/supabase";

const MAX_NAME_LENGTH = 60;
const MAX_DESCRIPTION_LENGTH = 500;
const INVITE_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I/l — avoids misreads
const INVITE_CODE_LENGTH = 8;
const BROWSE_PAGE_SIZE = 20;
const BROWSE_PAGE_SIZE_MAX = 50;

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

interface BrowseClubRow {
  id: string;
  name: string;
  description: string | null;
  privacy: string;
  invite_code: string | null;
  created_at: string;
}

/**
 * T4.1b (phase-4-backlog.md, v1 scoping session 2026-09-25): browse all clubs, newest-first, same
 * cursor-pagination shape `GET /api/social/posts` already established. `invite_code` is deliberately
 * NEVER included in the response — leaking it here would let anyone join an "invite-only" club without
 * ever being given the code, defeating the whole point of that privacy setting.
 */
export async function GET(request: Request) {
  const auth = await requireUser(request, "club.browse");
  if (isAuthFailure(auth)) return auth.response;

  const url = new URL(request.url);
  const beforeParam = url.searchParams.get("before");
  let before: Date | null = null;
  if (beforeParam !== null) {
    const parsed = new Date(beforeParam);
    if (Number.isNaN(parsed.getTime())) {
      return NextResponse.json({ error: "before must be a valid ISO 8601 timestamp" }, { status: 400 });
    }
    before = parsed;
  }

  const limitParam = url.searchParams.get("limit");
  let limit = BROWSE_PAGE_SIZE;
  if (limitParam !== null) {
    const parsed = Number(limitParam);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > BROWSE_PAGE_SIZE_MAX) {
      return NextResponse.json(
        { error: `limit must be an integer between 1 and ${BROWSE_PAGE_SIZE_MAX}` },
        { status: 400 }
      );
    }
    limit = parsed;
  }

  let query = supabaseAdmin
    .from("club")
    .select("id, name, description, privacy, invite_code, created_at")
    .order("created_at", { ascending: false });
  if (before) {
    query = query.lt("created_at", before.toISOString());
  }
  const { data, error } = await query.limit(limit + 1);
  if (error) {
    return NextResponse.json({ error: "Could not load clubs" }, { status: 500 });
  }

  const rows = (data ?? []) as unknown as BrowseClubRow[];
  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;

  const clubIds = page.map((row) => row.id);
  const memberCounts = new Map<string, number>();
  if (clubIds.length > 0) {
    const { data: memberRows, error: memberError } = await supabaseAdmin
      .from("club_member")
      .select("club_id")
      .in("club_id", clubIds);
    if (memberError) {
      return NextResponse.json({ error: "Could not load member counts" }, { status: 500 });
    }
    for (const row of (memberRows ?? []) as { club_id: string }[]) {
      memberCounts.set(row.club_id, (memberCounts.get(row.club_id) ?? 0) + 1);
    }
  }

  return NextResponse.json({
    clubs: page.map((row) => ({
      club_id: row.id,
      name: row.name,
      description: row.description,
      privacy: row.privacy,
      member_count: memberCounts.get(row.id) ?? 0,
      created_at: row.created_at,
    })),
    has_more: hasMore,
    next_before: hasMore && page.length > 0 ? page[page.length - 1]!.created_at : null,
  });
}
