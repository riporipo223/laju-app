import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

const MAX_CAPTION_LENGTH = 280;
const FEED_PAGE_SIZE = 20;
const FEED_PAGE_SIZE_MAX = 50;

interface CreatePostBody {
  run_id?: unknown;
  caption?: unknown;
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

  const { run_id, caption } = body;
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

  const { data: post, error: insertError } = await supabaseAdmin
    .from("social_post")
    .insert({ user_id: user.id, run_id, caption: trimmedCaption || null })
    .select("id, run_id, caption, created_at")
    .single<{ id: string; run_id: string; caption: string | null; created_at: string }>();

  if (insertError || !post) {
    return NextResponse.json({ error: "Could not create post" }, { status: 500 });
  }

  return NextResponse.json(
    { post_id: post.id, run_id: post.run_id, caption: post.caption, created_at: post.created_at },
    { status: 201 }
  );
}

const FEED_SELECT =
  "id, user_id, run_id, caption, created_at, " +
  "author:user_id(username, display_name, avatar_url), " +
  "run:run_id(distance_meters, duration_seconds, avg_pace_sec_per_km, final_points_awarded)";

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
}

/**
 * T4.15: the public feed (v1 has no other audience to filter by). Cursor-paginated on `created_at`
 * DESC (newest first), same "fetch PAGE_SIZE + 1 to detect has_more without a COUNT query" pattern as
 * `GET /api/runs`'s reconciliation endpoint. `like_count`/`liked_by_caller` are computed with one extra
 * batched query over the page's post ids rather than N+1 per-post queries.
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

  let query = supabaseAdmin.from("social_post").select(FEED_SELECT).order("created_at", { ascending: false });
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
      created_at: row.created_at,
      like_count: likeCounts.get(row.id) ?? 0,
      liked_by_caller: likedByCaller.has(row.id),
    })),
    has_more: hasMore,
    next_before: hasMore && page.length > 0 ? page[page.length - 1]!.created_at : null,
  });
}
