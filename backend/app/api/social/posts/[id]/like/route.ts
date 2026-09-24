import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

/** `null` return means the count query itself failed — callers turn that into a 500, never a throw. */
async function likeCount(postId: string): Promise<number | null> {
  const { count, error } = await supabaseAdmin
    .from("social_post_like")
    .select("*", { count: "exact", head: true })
    .eq("post_id", postId);
  return error ? null : (count ?? 0);
}

/**
 * T4.15: like a post. Idempotent — liking an already-liked post is a no-op that still returns 200 with
 * the current count, not an error; `social_post_like`'s composite primary key (migration) is what makes
 * `ignoreDuplicates` safe here instead of a prior existence check.
 */
export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "social.post.like");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  const { id } = await context.params;

  const { data: post, error: postError } = await supabaseAdmin
    .from("social_post")
    .select("id")
    .eq("id", id)
    .maybeSingle();
  if (postError) {
    return NextResponse.json({ error: "Could not look up post" }, { status: 500 });
  }
  if (!post) {
    return NextResponse.json({ error: "Post not found" }, { status: 404 });
  }

  const { error: likeError } = await supabaseAdmin
    .from("social_post_like")
    .upsert({ post_id: id, user_id: user.id }, { onConflict: "post_id,user_id", ignoreDuplicates: true });
  if (likeError) {
    return NextResponse.json({ error: "Could not like post" }, { status: 500 });
  }

  const count = await likeCount(id);
  if (count === null) {
    return NextResponse.json({ error: "Could not count likes" }, { status: 500 });
  }
  return NextResponse.json({ post_id: id, liked: true, like_count: count });
}

/** T4.15: unlike. Also idempotent — unliking a post that was never liked by this caller still returns 200. */
export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "social.post.like");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  const { id } = await context.params;

  const { error } = await supabaseAdmin.from("social_post_like").delete().eq("post_id", id).eq("user_id", user.id);
  if (error) {
    return NextResponse.json({ error: "Could not unlike post" }, { status: 500 });
  }

  const count = await likeCount(id);
  if (count === null) {
    return NextResponse.json({ error: "Could not count likes" }, { status: 500 });
  }
  return NextResponse.json({ post_id: id, liked: false, like_count: count });
}
