import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

/**
 * T4.15 (v1 scoping session, phase-4-backlog.md): "Moderation: delete-own-post only. No report/block/
 * admin review in v1." The `user_id` filter is what makes this delete-OWN-post specifically — a caller
 * who isn't the author gets the same 404 as a post that doesn't exist at all, never a 403, so a caller
 * can't use this endpoint to probe which post ids exist.
 */
export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "social.post.delete");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  const { id } = await context.params;

  const { data, error } = await supabaseAdmin
    .from("social_post")
    .delete()
    .eq("id", id)
    .eq("user_id", user.id)
    .select("id");

  if (error) {
    return NextResponse.json({ error: "Could not delete post" }, { status: 500 });
  }
  if (!data || data.length === 0) {
    return NextResponse.json({ error: "Post not found" }, { status: 404 });
  }

  return NextResponse.json({ post_id: id, deleted: true });
}
