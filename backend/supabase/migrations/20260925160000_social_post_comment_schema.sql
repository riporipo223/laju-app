-- T4.16 — Comment on social feed posts (phase-4-backlog.md, depends on T4.15).
--
-- ============================================================================
-- APPLIED 2026-09-25. VERIFIED LIVE 2026-09-25: 3/5 checks passed, 2 blocked.
-- - social_post_comment table structure confirmed (information_schema.columns)
-- - Index on post_id, user_id, plus the PK's own index confirmed (pg_indexes)
-- - RLS enabled confirmed (pg_class.relrowsecurity)
-- - Content-length CHECK rejection, and cascade-delete-on-post-delete: NOT
--   verified — both need an INSERT/real post row, which this session's write
--   classifier blocked (same class of block every migration this session
--   hit). Not claimed passed. Both are standard Postgres CHECK/FK-cascade
--   behavior, low risk but genuinely unexercised.
-- Backend API: GET/POST/DELETE /api/social/posts/[id]/comments — 13/13 tests
-- pass (mocked, not exercised against the live database either — same gap).
-- ============================================================================
--
-- Scope note (v1, 2026-09-25 scoping): flat comments only (no nested replies —
-- Instagram-style, not Reddit-style, matches the brief's simplest useful
-- shape). Delete-own-comment only, same moderation posture T4.15 chose for
-- posts (no report/block/admin review in v1). 280-char limit, same as
-- `social_post.caption`. No approval/moderation gate before a comment
-- appears — unlike a post (which needs a validated/approved run), a comment
-- has no anti-cheat-relevant claim to verify, so there is nothing to gate on.
--
-- `post_id` cascades on delete (deleting a post should delete its comments —
-- same reasoning `activity_detail.social_post_id` already uses). `user_id`
-- has no ON DELETE clause: account deletion never deletes rows here, it
-- anonymizes the `user` row instead (T2.22) — same posture `subscription`
-- and `social_post` already documented, no FK action needed for it.
--
-- RLS: enabled, zero grants to anon/authenticated — same pattern EVERY table
-- in this schema uses (20260919150457_enable_rls_deny_anon.sql), not
-- per-role SELECT/DELETE policies. All access goes through the Vercel API's
-- service_role key (bypasses RLS, scopes queries in code) — the "owner can
-- delete their own comment, anyone authenticated can read" rule is enforced
-- in `DELETE /api/social/posts/[id]/comments/[commentId]`'s own ownership
-- check, not a Postgres policy, for the same reason every other table here
-- makes that same choice: one enforcement path (the API), not two.

begin;

create table "social_post_comment" (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references "social_post" (id) on delete cascade,
  user_id uuid not null references "user" (id),
  content text not null check (char_length(content) > 0 and char_length(content) <= 280),
  created_at timestamptz not null default now()
);

-- A post's comment list, ordered oldest-first (GET /api/social/posts/[id]/comments).
create index "social_post_comment_post_id_idx" on "social_post_comment" (post_id);

-- account-deletion-adjacent lookups and "my comments" style queries, if ever needed.
create index "social_post_comment_user_id_idx" on "social_post_comment" (user_id);

alter table "social_post_comment" enable row level security;

revoke all on table "social_post_comment" from anon, authenticated;

commit;

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- begin;
--
-- drop table if exists "social_post_comment";
--
-- commit;
--
-- Pure rollback of an empty, newly-created table — no data-loss risk, since
-- nothing has ever written to this table until this migration is applied.

-- ============================================================================
-- VERIFICATION (run after applying — required real evidence, same discipline
-- as every other migration here. NONE of this has been run yet; do not mark
-- T4.16's migration done anywhere until it has.)
-- ============================================================================
-- Expect 5 columns:
--   select column_name, data_type, is_nullable from information_schema.columns
--    where table_schema = 'public' and table_name = 'social_post_comment'
--    order by ordinal_position;
--
-- Expect 2 indexes (plus the PK's own implicit index):
--   select indexname, indexdef from pg_indexes
--    where schemaname = 'public' and tablename = 'social_post_comment';
--
-- Expect rowsecurity = true:
--   select relname, relrowsecurity from pg_class where relname = 'social_post_comment';
--
-- Expect an over-length comment to be genuinely refused (inside begin/rollback,
-- a real post id and user id):
--   insert into "social_post_comment" (post_id, user_id, content)
--   values ('<real-post-id>', '<real-user-id>', repeat('x', 281));
--   -- ERROR: new row for relation "social_post_comment" violates check
--   -- constraint "social_post_comment_content_check"
--
-- Expect deleting a post to cascade-delete its comments:
--   delete from "social_post" where id = '<real-post-id>';
--   select count(*) from "social_post_comment" where post_id = '<real-post-id>'; -- expect 0
