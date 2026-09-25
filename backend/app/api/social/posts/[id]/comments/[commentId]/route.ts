import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

/**
 * T4.16: delete-own-comment only (v1 scope, same moderation posture as T4.15's delete-own-post) — the
 * server scopes this to the caller's own comments and answers 404 either way, never a 403 (a non-owner
 * gets the same response as a comment that never existed, no leaked "this exists but isn't yours" signal
 * — same shape `DELETE /api/social/posts/[id]` already uses).
 */
export async function DELETE(request: Request, context: { params: Promise<{ id: string; commentId: string }> }) {
  const auth = await requireUser(request, "social.comment.delete");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  const { commentId } = await context.params;

  const { data, error } = await supabaseAdmin
    .from("social_post_comment")
    .delete()
    .eq("id", commentId)
    .eq("user_id", user.id)
    .select("id")
    .maybeSingle<{ id: string }>();
  if (error) {
    return NextResponse.json({ error: "Could not delete comment" }, { status: 500 });
  }
  if (!data) {
    return NextResponse.json({ error: "Comment not found" }, { status: 404 });
  }

  return NextResponse.json({ comment_id: data.id, deleted: true });
}
