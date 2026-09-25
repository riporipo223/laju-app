-- T4.15 — Social Feed data model (phase-4-backlog.md's 2026-09-24 v1 scoping session).
--
-- ============================================================================
-- APPLIED 2026-09-24. VERIFIED LIVE 2026-09-25: 6/6 checks passed.
-- - Tables + RLS confirmed (information_schema + pg_class)
-- - V3: flagged/rejected run blocked by trigger — P0001 "run ... has status
--   flagged — only validated/approved runs can be posted (T4.15 v1 AC)"
-- - V4: cross-user posting blocked by trigger — P0001 "run ... does not
--   belong to user ... (T4.15 v1: can only post your own run)"
-- - V5: duplicate like rejected — 23505 duplicate key value violates unique
--   constraint "social_post_like_pkey"
-- - V6: cascade delete on post deletion — count_after = 0
-- See backend/scripts/verify-t4.15-social-triggers.sql for the verification
-- scripts. Verification performed manually via Supabase SQL Editor against
-- production.
-- ============================================================================
--
-- Scope note (v1 decisions, phase-4-backlog.md T4.15): Public audience only
-- (no Circle/Club/Private column — nothing to store for an audience that
-- doesn't exist yet); no Premium card-differentiation column; delete-own-post
-- is the only moderation path (no report/block/review tables). A post can
-- only be created from a run whose status is 'validated' or 'approved' —
-- enforced below by a trigger, not just the API layer, matching this repo's
-- preference for DB-level invariants (club_war_club's max-3-clubs /
-- one-open-war triggers, season_single_active).

begin;

-- ============================================================
-- social_post
-- ============================================================
-- One row per posted achievement. No audience/visibility column (Public-only
-- in v1 — see scope note). `caption` is optional free text, no length cap
-- decided yet beyond a generous sanity bound enforced here, not chosen as a
-- real product decision.
--
-- Deliberately holds no denormalized run stats (distance/pace/points): unlike
-- LeaderboardEntry.frozen_display_name (database-api-spec.md §1), there is no
-- requirement yet that a post's displayed numbers survive independently of
-- the run row, and `run` rows are never deleted (account-deletion.ts only
-- clears `gps_route`) — so the API reads them via a live join. Revisit if a
-- future requirement needs the post to freeze its stats at post time.
create table "social_post" (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references "user" (id),
  run_id uuid not null references "run" (id),
  caption text check (char_length(caption) <= 280),
  created_at timestamptz not null default now()
);

-- Feed pagination (created_at DESC, newest first) and account-deletion's
-- delete-by-user-id sweep.
create index "social_post_created_at_idx" on "social_post" (created_at desc);
create index "social_post_user_id_idx" on "social_post" (user_id);

-- AC (v1 scoping session): "A run can only be posted once it's validated/
-- approved (not flagged/rejected)". A CHECK constraint can't reach another
-- table's column, so this is a trigger. Also enforces the caller can only
-- post their OWN run — the API already knows this from `requireUser` before
-- it ever inserts, but this is the DB-level backstop, same philosophy as
-- club_war_club's ownership-adjacent triggers.
create function "social_post_enforce_run_ownership_and_status"()
returns trigger
language plpgsql
as $$
declare
  run_owner_id uuid;
  run_status text;
begin
  select user_id, status into run_owner_id, run_status from "run" where id = new.run_id;

  if run_owner_id is null then
    raise exception 'run % does not exist', new.run_id;
  end if;
  if run_owner_id <> new.user_id then
    raise exception 'run % does not belong to user % (T4.15 v1: can only post your own run)', new.run_id, new.user_id;
  end if;
  if run_status not in ('validated', 'approved') then
    raise exception 'run % has status % — only validated/approved runs can be posted (T4.15 v1 AC)', new.run_id, run_status;
  end if;

  return new;
end;
$$;

create trigger "social_post_ownership_status_trigger"
before insert on "social_post"
for each row
execute function "social_post_enforce_run_ownership_and_status"();

-- ============================================================
-- social_post_like
-- ============================================================
-- `post_id` cascades on `social_post` delete — deleting a post (owner
-- delete-own-post, or account-deletion.ts's bulk delete) must not leave
-- orphaned like rows. `on delete cascade` is why account-deletion.ts's own
-- comment says "social_post_like cascades on social_post deletion
-- (migration)" and only separately deletes likes this user made on OTHER
-- users' posts.
--
-- Composite primary key (post_id, user_id) is the "like once" invariant —
-- same reasoning as club_member's user_id-as-PK for one-club-per-user: a
-- structural fact, not a business rule that could plausibly change, so
-- enforced here rather than left to the API to de-duplicate.
create table "social_post_like" (
  post_id uuid not null references "social_post" (id) on delete cascade,
  user_id uuid not null references "user" (id),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- Account-deletion's delete-by-user-id sweep for likes this user made on
-- others' posts (`post_id`-first lookups are already covered by the PK).
create index "social_post_like_user_id_idx" on "social_post_like" (user_id);

-- ============================================================
-- RLS — matches 20260919150457_enable_rls_deny_anon.sql's established
-- policy: RLS enabled, zero grants to anon/authenticated. All access goes
-- through the Vercel API's service_role key, which bypasses RLS and scopes
-- queries in code — applied here so these 2 new tables don't reopen the
-- hole SEC-11 closed.
-- ============================================================
alter table "social_post" enable row level security;
alter table "social_post_like" enable row level security;

revoke all on table "social_post", "social_post_like" from anon, authenticated;

commit;

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- begin;
--
-- drop trigger if exists "social_post_ownership_status_trigger" on "social_post";
-- drop function if exists "social_post_enforce_run_ownership_and_status"();
-- drop table if exists "social_post_like";
-- drop table if exists "social_post";
--
-- commit;
--
-- Pure rollback of empty, newly-created tables — no data-loss risk, since
-- nothing has ever written to these tables until this migration is applied.

-- ============================================================================
-- VERIFICATION (run after applying — required real evidence, same discipline
-- as T4.2a/T4.20a. NONE of this has been run yet; do not mark T4.15's
-- migration done anywhere until it has.)
-- ============================================================================
-- Expect 2 rows:
--   select table_name from information_schema.tables
--    where table_schema = 'public' and table_name in ('social_post', 'social_post_like');
--
-- Expect rowsecurity = true for both:
--   select relname, relrowsecurity from pg_class
--    where relname in ('social_post', 'social_post_like');
--
-- Expect a flagged/rejected run to be genuinely refused (inside begin/rollback, real user + run ids):
--   insert into "social_post" (user_id, run_id) values ('<real-user-id>', '<a-flagged-run-id>');
--   -- ERROR: run ... has status flagged — only validated/approved runs can be posted (T4.15 v1 AC)
--
-- Expect posting someone else's run to be genuinely refused:
--   insert into "social_post" (user_id, run_id) values ('<user-a-id>', '<user-bs-validated-run-id>');
--   -- ERROR: run ... does not belong to user ... (T4.15 v1: can only post your own run)
--
-- Expect a double-like to be genuinely rejected:
--   insert into "social_post_like" (post_id, user_id) values ('<real-post-id>', '<real-user-id>');
--   insert into "social_post_like" (post_id, user_id) values ('<real-post-id>', '<real-user-id>');
--   -- second insert => ERROR: duplicate key value violates unique constraint "social_post_like_pkey"
--
-- Expect deleting a post to cascade-delete its likes:
--   delete from "social_post" where id = '<real-post-id>';
--   select count(*) from "social_post_like" where post_id = '<real-post-id>'; -- expect 0
