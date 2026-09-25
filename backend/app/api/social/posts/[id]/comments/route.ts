import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

const MAX_CONTENT_LENGTH = 280;
const PAGE_SIZE = 50;

interface CreateCommentBody {
  content?: unknown;
}

interface CommentRow {
  id: string;
  post_id: string;
  user_id: string;
  content: string;
  created_at: string;
  author: { username: string | null; display_name: string | null; avatar_url: string | null } | null;
}

/**
 * T4.16 (phase-4-backlog.md, v1 scoping session 2026-09-25): a post's comments, oldest-first (matches a
 * chat/thread reading order, not a feed's newest-first). Flat — no nested replies (v1 scope). No
 * cursor pagination like the feed itself has (T4.15): a single post's comment count is expected to stay
 * small in v1 (no reason yet to build a second pagination scheme before one is needed) — capped at
 * `PAGE_SIZE`.
 */
export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "social.comment.list");
  if (isAuthFailure(auth)) return auth.response;

  const { id } = await context.params;

  const { data, error } = await supabaseAdmin
    .from("social_post_comment")
    .select("id, post_id, user_id, content, created_at, author:user_id(username, display_name, avatar_url)")
    .eq("post_id", id)
    .order("created_at", { ascending: true })
    .limit(PAGE_SIZE);
  if (error) {
    return NextResponse.json({ error: "Could not load comments" }, { status: 500 });
  }

  const rows = (data ?? []) as unknown as CommentRow[];
  return NextResponse.json({
    comments: rows.map((row) => ({
      comment_id: row.id,
      post_id: row.post_id,
      user_id: row.user_id,
      username: row.author?.username ?? null,
      display_name: row.author?.display_name ?? null,
      avatar_url: row.author?.avatar_url ?? null,
      content: row.content,
      created_at: row.created_at,
    })),
  });
}

/**
 * T4.16: add a comment to a post. Unlike a post itself, a comment has no anti-cheat-relevant claim to
 * verify — it appears immediately, no validated/approved gate (v1 scoping note, same file as GET above).
 * Any authenticated caller may comment on any post that exists (no ownership check on the post) —
 * commenting is not restricted to the post's own author or the feed's audience.
 */
export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "social.comment.create");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  const { id } = await context.params;

  let body: CreateCommentBody;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { content } = body;
  if (typeof content !== "string" || content.trim().length === 0) {
    return NextResponse.json({ error: "content is required" }, { status: 400 });
  }
  const trimmedContent = content.trim();
  if (trimmedContent.length > MAX_CONTENT_LENGTH) {
    return NextResponse.json({ error: `content may be at most ${MAX_CONTENT_LENGTH} characters` }, { status: 400 });
  }

  const { data: post, error: postError } = await supabaseAdmin
    .from("social_post")
    .select("id")
    .eq("id", id)
    .maybeSingle<{ id: string }>();
  if (postError) {
    return NextResponse.json({ error: "Could not look up post" }, { status: 500 });
  }
  if (!post) {
    return NextResponse.json({ error: "Post not found" }, { status: 404 });
  }

  const { data: comment, error: insertError } = await supabaseAdmin
    .from("social_post_comment")
    .insert({ post_id: id, user_id: user.id, content: trimmedContent })
    .select("id, post_id, user_id, content, created_at")
    .single<{ id: string; post_id: string; user_id: string; content: string; created_at: string }>();
  if (insertError || !comment) {
    return NextResponse.json({ error: "Could not create comment" }, { status: 500 });
  }

  return NextResponse.json(
    {
      comment_id: comment.id,
      post_id: comment.post_id,
      user_id: comment.user_id,
      content: comment.content,
      created_at: comment.created_at,
    },
    { status: 201 }
  );
}
