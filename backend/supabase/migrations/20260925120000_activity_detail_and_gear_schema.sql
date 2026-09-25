-- T4.21 — Save Activity flow: `gear` (shoe) + `activity_detail` (title/description/private
-- notes/map type/visibility per post), phase-4-backlog.md's 2026-09-25 v1 scoping session.
--
-- ============================================================================
-- WRITTEN 2026-09-25. NOT YET APPLIED to production, NOT YET VERIFIED live —
-- same two-step gate as 20260924220000_social_feed_schema.sql (T4.15) and
-- every other migration in this repo: write inert -> review -> apply + record
-- real evidence as a separate step. Whoever applies this MUST update this
-- banner with genuine verification output (see VERIFICATION below) before
-- checking T4.21's migration off as done anywhere in tasks/*.
-- ============================================================================
--
-- Scope note (v1 decisions, phase-4-backlog.md T4.21, 2026-09-25 scoping session):
-- - `activity_detail` is a separate 1:1 side-table keyed on `social_post_id` (not new columns on
--   `social_post`), decided specifically so `private_notes` never sits in the same row a public feed
--   query reads from — a column-list mistake on `social_post` risks leaking it, a table the public
--   feed query never joins cannot.
-- - Title/description/private_notes: all optional, same as the existing `caption` column.
-- - Map Type v1: 'standard' / 'activity_heat' only — no 3D option exists yet (T4.20's Premium
--   verification is a stub that always returns false, blocked on Apple Developer Program enrollment
--   same as T4.2b; shipping a 3D value now would be a dead end with nothing to gate against).
-- - Visibility v1: 'public' / 'private' only — no 'friends' value exists yet (the app has no
--   friend/follow graph, same gap T4.15 named when deferring Circle/Club audience).
-- - `gear` is a separate one-to-many table (user -> many gear rows), not a column on `user`, because
--   the product brief explicitly wants "Add Gear" for a second shoe — a single-gear column on `user`
--   cannot express that. `brand` is `text`, not a DB enum or CHECK-constrained list: the v1 brand list
--   (Nike, Adidas, Hoka, Asics, Brooks, New Balance, Saucony, Puma, Mizuno, On, Under Armour, Other) is
--   validated at the API layer, deliberately, so adding a 13th brand later is an API-layer change, not
--   a migration.

begin;

-- ============================================================
-- gear
-- ============================================================
-- One row per shoe a user has added (via Save Activity's "Add Gear" or the profile screen — both write
-- to the same table, there is no run-scoped copy). `model`/`size` are free text (no shoe dataset, per
-- the v1 brief — a user types "AirMax 95" or "P6000" themselves).
create table "gear" (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references "user" (id),
  brand text not null,
  model text,
  size text,
  created_at timestamptz not null default now()
);

-- Profile's gear list read, and account-deletion's delete-by-user-id sweep.
create index "gear_user_id_idx" on "gear" (user_id);

-- ============================================================
-- activity_detail
-- ============================================================
-- 1:1 with `social_post` — `social_post_id` is the primary key (not a separate surrogate `id`), same
-- reasoning this repo already uses for `social_post_like`'s composite PK and `club_member`'s
-- user_id-as-PK: a structural one-to-one fact, not a business rule that could plausibly become
-- one-to-many, so enforced by the key itself rather than left to the API to keep unique.
--
-- `gear_id` is nullable and `on delete set null` (not cascade): deleting a shoe from your profile later
-- must not delete a past post's activity detail, it should just stop naming a shoe.
create table "activity_detail" (
  social_post_id uuid primary key references "social_post" (id) on delete cascade,
  title text,
  description text,
  private_notes text,
  map_type text not null default 'standard' check (map_type in ('standard', 'activity_heat')),
  visibility text not null default 'public' check (visibility in ('public', 'private')),
  gear_id uuid references "gear" (id) on delete set null,
  created_at timestamptz not null default now()
);

create index "activity_detail_gear_id_idx" on "activity_detail" (gear_id);

-- ============================================================
-- RLS — matches 20260919150457_enable_rls_deny_anon.sql's established policy: RLS enabled, zero grants
-- to anon/authenticated. All access goes through the Vercel API's service_role key, which bypasses RLS
-- and scopes queries in code — applied here so these 2 new tables don't reopen the hole SEC-11 closed.
-- ============================================================
alter table "gear" enable row level security;
alter table "activity_detail" enable row level security;

revoke all on table "gear", "activity_detail" from anon, authenticated;

commit;

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- begin;
--
-- drop table if exists "activity_detail";
-- drop table if exists "gear";
--
-- commit;
--
-- Pure rollback of empty, newly-created tables — no data-loss risk, since nothing has ever written to
-- these tables until this migration is applied.

-- ============================================================================
-- VERIFICATION (run after applying — required real evidence, same discipline as T4.15/T4.2a/T4.20a.
-- NONE of this has been run yet; do not mark T4.21's migration done anywhere until it has.)
-- ============================================================================
-- Expect 2 rows:
--   select table_name from information_schema.tables
--    where table_schema = 'public' and table_name in ('gear', 'activity_detail');
--
-- Expect rowsecurity = true for both:
--   select relname, relrowsecurity from pg_class
--    where relname in ('gear', 'activity_detail');
--
-- Expect a second activity_detail row for the same post to be genuinely refused (inside begin/rollback,
-- real post id):
--   insert into "activity_detail" (social_post_id) values ('<real-social-post-id>');
--   insert into "activity_detail" (social_post_id) values ('<same-social-post-id>');
--   -- second insert => ERROR: duplicate key value violates unique constraint "activity_detail_pkey"
--
-- Expect an invalid map_type/visibility value to be genuinely refused:
--   insert into "activity_detail" (social_post_id, map_type) values ('<real-social-post-id>', '3d');
--   -- ERROR: new row for relation "activity_detail" violates check constraint "activity_detail_map_type_check"
--
-- Expect deleting a post to cascade-delete its activity_detail:
--   delete from "social_post" where id = '<real-post-id>';
--   select count(*) from "activity_detail" where social_post_id = '<real-post-id>'; -- expect 0
--
-- Expect deleting a gear row to null out (not delete) activity_detail referencing it:
--   delete from "gear" where id = '<real-gear-id>';
--   select gear_id from "activity_detail" where gear_id = '<real-gear-id>'; -- expect 0 rows (nulled out, not matched)
