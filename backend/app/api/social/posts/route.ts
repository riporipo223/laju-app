import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

const MAX_CAPTION_LENGTH = 280;
const MAX_TITLE_LENGTH = 100;
const MAX_DESCRIPTION_LENGTH = 2000;
const MAX_PRIVATE_NOTES_LENGTH = 2000;
const FEED_PAGE_SIZE = 20;
const FEED_PAGE_SIZE_MAX = 50;

/** T4.21 (20260925120000_activity_detail_and_gear_schema.sql): must match the DB CHECK constraints. */
const VALID_MAP_TYPES = ["standard", "activity_heat"] as const;
const VALID_VISIBILITIES = ["public", "private"] as const;

interface CreatePostBody {
  run_id?: unknown;
  caption?: unknown;
  title?: unknown;
  description?: unknown;
  private_notes?: unknown;
  map_type?: unknown;
  visibility?: unknown;
  gear_id?: unknown;
}

interface RunOwnershipRow {
  user_id: string;
  status: string;
}

/**
 * T4.15 (v1 scoping session, phase-4-backlog.md): create a post from one of the caller's own runs.
 * "A run can only be posted once it's validated/approved (not flagged/rejected)" is checked explicitly
 * here for a clean error response; `social_post_ownership_status_trigger`
 * (20260924220000_social_feed_schema.sql) is the DB-level backstop for a race — e.g. the run gets
 * flagged by the anti-cheat pipeline between this check and the insert.
 *
 * No audience field on the request body: v1 is Public-only (Circle/Club/Private all deferred — no Club
 * exists yet), so there is nothing to choose.
 *
 * T4.21 (phase-4-backlog.md, 2026-09-25): every new post also gets a 1:1 `activity_detail` row (Save
 * Activity's title/description/private_notes/map_type/visibility/gear_id) — always inserted, even when
 * every field is left at its default, so `GET`'s feed join never has to special-case "created before
 * T4.21 existed" vs "created with nothing filled in". `gear_id`, if given, must belong to the caller —
 * same ownership-check shape as the run above, just without a DB-level trigger backstop (gear has no
 * ownership/status invariant worth enforcing at the DB level the way a run's does).
 */
export async function POST(request: Request) {
  const auth = await requireUser(request, "social.post.create");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  let body: CreatePostBody;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { run_id, caption, title, description, private_notes, map_type, visibility, gear_id } = body;
  if (typeof run_id !== "string" || run_id.length === 0) {
    return NextResponse.json({ error: "run_id is required" }, { status: 400 });
  }
  if (caption !== undefined && caption !== null && typeof caption !== "string") {
    return NextResponse.json({ error: "caption must be a string" }, { status: 400 });
  }
  const trimmedCaption = typeof caption === "string" ? caption.trim() : null;
  if (trimmedCaption !== null && trimmedCaption.length > MAX_CAPTION_LENGTH) {
    return NextResponse.json({ error: `caption may be at most ${MAX_CAPTION_LENGTH} characters` }, { status: 400 });
  }

  for (const [name, value, max] of [
    ["title", title, MAX_TITLE_LENGTH],
    ["description", description, MAX_DESCRIPTION_LENGTH],
    ["private_notes", private_notes, MAX_PRIVATE_NOTES_LENGTH],
  ] as const) {
    if (value !== undefined && value !== null && typeof value !== "string") {
      return NextResponse.json({ error: `${name} must be a string` }, { status: 400 });
    }
    if (typeof value === "string" && value.trim().length > max) {
      return NextResponse.json({ error: `${name} may be at most ${max} characters` }, { status: 400 });
    }
  }
  const trimmedTitle = typeof title === "string" ? title.trim() || null : null;
  const trimmedDescription = typeof description === "string" ? description.trim() || null : null;
  const trimmedPrivateNotes = typeof private_notes === "string" ? private_notes.trim() || null : null;

  const resolvedMapType = map_type ?? "standard";
  if (!VALID_MAP_TYPES.includes(resolvedMapType as (typeof VALID_MAP_TYPES)[number])) {
    return NextResponse.json({ error: `map_type must be one of: ${VALID_MAP_TYPES.join(", ")}` }, { status: 400 });
  }
  const resolvedVisibility = visibility ?? "public";
  if (!VALID_VISIBILITIES.includes(resolvedVisibility as (typeof VALID_VISIBILITIES)[number])) {
    return NextResponse.json({ error: `visibility must be one of: ${VALID_VISIBILITIES.join(", ")}` }, { status: 400 });
  }
  if (gear_id !== undefined && gear_id !== null && typeof gear_id !== "string") {
    return NextResponse.json({ error: "gear_id must be a string" }, { status: 400 });
  }

  const { data: run, error: runError } = await supabaseAdmin
    .from("run")
    .select("user_id, status")
    .eq("id", run_id)
    .maybeSingle<RunOwnershipRow>();
  if (runError) {
    return NextResponse.json({ error: "Could not look up run" }, { status: 500 });
  }
  if (!run) {
    return NextResponse.json({ error: "Run not found" }, { status: 404 });
  }
  if (run.user_id !== user.id) {
    return NextResponse.json({ error: "You can only post your own runs" }, { status: 403 });
  }
  if (run.status !== "validated" && run.status !== "approved") {
    return NextResponse.json({ error: "Only a validated or approved run can be posted" }, { status: 422 });
  }

  let resolvedGearId: string | null = null;
  if (typeof gear_id === "string" && gear_id.length > 0) {
    const { data: gear, error: gearError } = await supabaseAdmin
      .from("gear")
      .select("user_id")
      .eq("id", gear_id)
      .maybeSingle<{ user_id: string }>();
    if (gearError) {
      return NextResponse.json({ error: "Could not look up gear" }, { status: 500 });
    }
    if (!gear) {
      return NextResponse.json({ error: "Gear not found" }, { status: 404 });
    }
    if (gear.user_id !== user.id) {
      return NextResponse.json({ error: "You can only use your own gear" }, { status: 403 });
    }
    resolvedGearId = gear_id;
  }

  const { data: post, error: insertError } = await supabaseAdmin
    .from("social_post")
    .insert({ user_id: user.id, run_id, caption: trimmedCaption || null })
    .select("id, run_id, caption, created_at")
    .single<{ id: string; run_id: string; caption: string | null; created_at: string }>();

  if (insertError || !post) {
    return NextResponse.json({ error: "Could not create post" }, { status: 500 });
  }

  const { error: detailError } = await supabaseAdmin.from("activity_detail").insert({
    social_post_id: post.id,
    title: trimmedTitle,
    description: trimmedDescription,
    private_notes: trimmedPrivateNotes,
    map_type: resolvedMapType,
    visibility: resolvedVisibility,
    gear_id: resolvedGearId,
  });
  if (detailError) {
    return NextResponse.json({ error: "Post created but activity detail could not be saved" }, { status: 500 });
  }

  return NextResponse.json(
    {
      post_id: post.id,
      run_id: post.run_id,
      caption: post.caption,
      title: trimmedTitle,
      description: trimmedDescription,
      map_type: resolvedMapType,
      visibility: resolvedVisibility,
      gear_id: resolvedGearId,
      created_at: post.created_at,
    },
    { status: 201 }
  );
}

/**
 * T4.21: `activity_detail!inner` — safe as a plain inner join (not left) because the migration
 * (20260925120000_activity_detail_and_gear_schema.sql) backfills a row for every pre-existing post and
 * `POST` above always inserts one for every new post, so "no activity_detail row" never happens.
 * `private_notes` is deliberately never selected here — this is the public feed, not the post's own
 * author's view.
 */
const FEED_SELECT =
  "id, user_id, run_id, caption, created_at, " +
  "author:user_id(username, display_name, avatar_url), " +
  "run:run_id(distance_meters, duration_seconds, avg_pace_sec_per_km, final_points_awarded), " +
  "activity_detail!inner(title, description, map_type, visibility, gear_id)";

interface FeedRow {
  id: string;
  user_id: string;
  run_id: string;
  caption: string | null;
  created_at: string;
  author: { username: string | null; display_name: string | null; avatar_url: string | null } | null;
  run: {
    distance_meters: number;
    duration_seconds: number;
    avg_pace_sec_per_km: number;
    final_points_awarded: number;
  } | null;
  activity_detail: {
    title: string | null;
    description: string | null;
    map_type: string;
    visibility: string;
    gear_id: string | null;
  } | null;
}

/**
 * T4.15: the public feed (v1 has no other audience to filter by). Cursor-paginated on `created_at`
 * DESC (newest first), same "fetch PAGE_SIZE + 1 to detect has_more without a COUNT query" pattern as
 * `GET /api/runs`'s reconciliation endpoint. `like_count`/`liked_by_caller` are computed with one extra
 * batched query over the page's post ids rather than N+1 per-post queries.
 *
 * T4.21: filters out `visibility = 'private'` posts — the caller's own private posts are excluded here
 * too (a private post is "not published", not "published but only-you-can-see-it-in-the-feed"; there is
 * no separate "my activity" endpoint in this task's scope — phase-4-backlog.md T4.21 note).
 */
export async function GET(request: Request) {
  const auth = await requireUser(request, "social.post.list");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

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
  let limit = FEED_PAGE_SIZE;
  if (limitParam !== null) {
    const parsed = Number(limitParam);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > FEED_PAGE_SIZE_MAX) {
      return NextResponse.json(
        { error: `limit must be an integer between 1 and ${FEED_PAGE_SIZE_MAX}` },
        { status: 400 }
      );
    }
    limit = parsed;
  }

  let query = supabaseAdmin
    .from("social_post")
    .select(FEED_SELECT)
    .eq("activity_detail.visibility", "public")
    .order("created_at", { ascending: false });
  if (before) {
    query = query.lt("created_at", before.toISOString());
  }
  const { data, error } = await query.limit(limit + 1);
  if (error) {
    return NextResponse.json({ error: "Could not load feed" }, { status: 500 });
  }

  const rows = (data ?? []) as unknown as FeedRow[];
  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;

  const postIds = page.map((row) => row.id);
  const likeCounts = new Map<string, number>();
  const likedByCaller = new Set<string>();

  if (postIds.length > 0) {
    const { data: likeRows, error: likeError } = await supabaseAdmin
      .from("social_post_like")
      .select("post_id, user_id")
      .in("post_id", postIds);
    if (likeError) {
      return NextResponse.json({ error: "Could not load likes" }, { status: 500 });
    }
    for (const like of (likeRows ?? []) as { post_id: string; user_id: string }[]) {
      likeCounts.set(like.post_id, (likeCounts.get(like.post_id) ?? 0) + 1);
      if (like.user_id === user.id) likedByCaller.add(like.post_id);
    }
  }

  return NextResponse.json({
    posts: page.map((row) => ({
      post_id: row.id,
      user_id: row.user_id,
      username: row.author?.username ?? null,
      display_name: row.author?.display_name ?? null,
      avatar_url: row.author?.avatar_url ?? null,
      run_id: row.run_id,
      distance_meters: row.run?.distance_meters ?? null,
      duration_seconds: row.run?.duration_seconds ?? null,
      avg_pace_sec_per_km: row.run?.avg_pace_sec_per_km ?? null,
      final_points_awarded: row.run?.final_points_awarded ?? null,
      caption: row.caption,
      title: row.activity_detail?.title ?? null,
      description: row.activity_detail?.description ?? null,
      map_type: row.activity_detail?.map_type ?? "standard",
      gear_id: row.activity_detail?.gear_id ?? null,
      created_at: row.created_at,
      like_count: likeCounts.get(row.id) ?? 0,
      liked_by_caller: likedByCaller.has(row.id),
    })),
    has_more: hasMore,
    next_before: hasMore && page.length > 0 ? page[page.length - 1]!.created_at : null,
  });
}
