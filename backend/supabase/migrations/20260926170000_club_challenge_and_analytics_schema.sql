-- T4.1's Circle Challenge + Analytics data model (product-spec.md §4.24 AC11-AC15, AC24).
--
-- ============================================================================
-- APPLIED 2026-09-26 to production (`supabase db push`). Real evidence, all
-- 3 checks from this file's own VERIFICATION section below, run for real:
--   - both tables exist with RLS enabled (relrowsecurity = t): club_challenge,
--     club_membership_history (pg_class).
--   - club_challenge_one_open_per_club_idx genuinely rejected a second open
--     challenge for the same club: "duplicate key value violates unique
--     constraint club_challenge_one_open_per_club_idx".
--   - club_membership_history_open_stint_idx genuinely rejected a second open
--     stint for the same (club_id, user_id): "duplicate key value violates
--     unique constraint club_membership_history_open_stint_idx".
-- All three ran inside begin/rollback against temporary QA rows; confirmed
-- zero rows left behind afterward (club/club_challenge/club_membership_history
-- all count 0 immediately after).
--
-- Also repaired this session: 7 earlier migrations (20260923090000 through
-- 20260925160000) showed empty "remote" in `supabase migration list` despite
-- being genuinely live in production (confirmed by direct read-only query
-- against information_schema for every table/column each one creates, before
-- touching migration history) — their own commit history applied them
-- out-of-band, never through this CLI. `supabase migration repair --status
-- applied` synced the tracking table to match reality; this was the
-- prerequisite that let `db push` target only this migration instead of
-- re-attempting all 8.
-- ============================================================================
--
-- Scope note: this is schema only — no backend route reads or writes these
-- tables yet (that's the same session's follow-up commits, each with its own
-- TDD test suite). `club`/`club_member` already exist (20260923200000,
-- 20260925150000) and are only referenced here, not altered.
--
-- ============================================================================
-- Why TWO new tables, not one
-- ============================================================================
-- `club_challenge` is the obvious one: one row per challenge, its target and
-- deadline, current status.
--
-- `club_membership_history` is the non-obvious one, and exists ONLY because
-- of one specific product requirement (product-spec.md §4.24 AC13, "Full
-- mechanics" 2026-09-26): "the collective total only ever increases... a
-- member who leaves the Circle [keeps their past contribution counted], but
-- their own run/points data is never touched." To compute a challenge's
-- collective total correctly, the query needs to know, for every run, "was
-- this run's owner a member of this club AT THE TIME the run happened" — and
-- `club_member` only ever holds CURRENT membership (leaving/being kicked
-- deletes the row entirely, per `backend/app/api/clubs/[id]/members/
-- route.ts`'s DELETE handler). Once a member leaves, `club_member` has no
-- record they were ever in this club at all — so a live join against it
-- would silently drop their entire past contribution, which is exactly the
-- bug this table exists to prevent.
--
-- The alternative considered and rejected: a contribution ledger written at
-- run-submission/anti-cheat-resolution time (analogous to `point_transaction`,
-- ADR-0013's append-only pattern). Rejected because it means threading new
-- writes into the run submission and anti-cheat resolution pipelines
-- (`POST /api/runs`, `lib/anti-cheat/resolve-flagged-runs.ts`) — a much
-- larger blast radius than this feature's own files for a requirement that a
-- membership-span history satisfies just as correctly. `club_membership_history`
-- only needs write-hooks in the THREE existing Circle routes that already
-- create/end a membership (`POST /api/clubs` creating the owner's own row,
-- `POST /api/clubs/[id]/join`, and `DELETE /api/clubs/[id]/members`) — those
-- are edited in the same follow-up commit that adds challenge/analytics
-- reads, not here.
--
-- A user can join, leave, and rejoin the same club — `joined_at`/`left_at`
-- per row (not a single row per user) supports multiple stints correctly;
-- each stint's runs count independently within its own window.
--
-- The club has zero rows in production as of this writing (T4.1a's own
-- banner: "club has zero rows until T4.1's Create Club ships") — there is
-- no backfill concern for either table.

begin;

-- ============================================================
-- club_challenge
-- ============================================================
-- Status lifecycle (product-spec.md §4.24 AC13's "Full mechanics"):
--   active -> target_reached -> closed_success   (deadline passed, target WAS met at some point)
--   active -> closed_missed                       (deadline passed, target never met)
--   active|target_reached -> cancelled            (owner cancels, any time)
-- `target_reached` is NOT terminal — reaching the target before the deadline
-- does not close the challenge early (AC13: "does not end the challenge
-- early... all the way to the original deadline"); it is a display-only
-- milestone flag until the deadline actually passes. `closed_success` is only
-- reachable via `target_reached` first (a challenge closed by the deadline
-- job checks "was target_reached ever set" — not "is the total at/above
-- target right now", since the total never decreases anyway so those two
-- reads would agree once written, but this documents the field's own meaning
-- rather than relying on that coincidence).
--
-- target_value's unit depends on target_type, matching `run`'s own columns
-- (20260917162813_create_core_schema.sql) exactly so a progress query never
-- needs a conversion: 'distance' -> meters (matches `run.distance_meters`),
-- 'duration' -> seconds (matches `run.duration_seconds`).
create table "club_challenge" (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references "club" (id),
  name text not null,
  target_type text not null check (target_type in ('distance', 'duration')),
  target_value numeric not null check (target_value > 0),
  deadline timestamptz not null,
  status text not null default 'active'
    check (status in ('active', 'target_reached', 'closed_success', 'closed_missed', 'cancelled')),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz
);

create index "club_challenge_club_id_idx" on "club_challenge" (club_id);

-- At most one OPEN challenge per club (product-spec.md §4.24 AC13: "at most
-- one active challenge per club"). A partial unique index, not a trigger
-- (unlike club_war's max-3-clubs/one-open-war triggers, T4.2a) — this is a
-- simple "at most one row matching a condition" shape, which a partial
-- unique index expresses directly with no procedural code. 'active' and
-- 'target_reached' both count as open (see the status lifecycle note above);
-- 'closed_success'/'closed_missed'/'cancelled' are terminal and never block
-- a new challenge.
create unique index "club_challenge_one_open_per_club_idx"
  on "club_challenge" (club_id)
  where status in ('active', 'target_reached');

-- ============================================================
-- club_membership_history
-- ============================================================
-- See the file-level comment above for why this table exists at all.
-- `left_at is null` marks the currently-open stint for a user in a club —
-- there is at most one such row per (user_id, club_id) pair at any time
-- (enforced by the partial unique index below), but a user can have many
-- CLOSED stints (rejoining after leaving).
create table "club_membership_history" (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references "club" (id),
  user_id uuid not null references "user" (id),
  joined_at timestamptz not null,
  left_at timestamptz
);

create index "club_membership_history_club_id_idx" on "club_membership_history" (club_id);
create index "club_membership_history_user_id_idx" on "club_membership_history" (user_id);

-- At most one OPEN stint (left_at is null) per user per club — mirrors
-- `club_member`'s own "one row per user" invariant for the CURRENT stint;
-- this table additionally keeps every past stint once closed.
create unique index "club_membership_history_open_stint_idx"
  on "club_membership_history" (club_id, user_id)
  where left_at is null;

-- ============================================================
-- RLS — matches every other table in this schema (20260919150457_enable_rls_deny_anon.sql's
-- established policy): RLS enabled, zero grants to anon; every query in this codebase uses the
-- service-role key, which bypasses RLS and scopes queries in code.
-- ============================================================
alter table "club_challenge" enable row level security;
alter table "club_membership_history" enable row level security;

commit;

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- begin;
--
-- drop table if exists "club_membership_history";
-- drop table if exists "club_challenge";
--
-- commit;
--
-- Both tables have zero rows until the follow-up commits that read/write
-- them ship (no route exists yet as of this migration) — no data-loss risk
-- at the time this migration is written.

-- ============================================================================
-- VERIFICATION (run after applying — required real evidence, same discipline
-- as every other migration here. NONE of this has been run yet; do not mark
-- any Circle Challenge/Analytics task done anywhere until it has.)
-- ============================================================================
-- Expect both tables + RLS enabled:
--   select relname, relrowsecurity from pg_class
--    where relname in ('club_challenge', 'club_membership_history');
--
-- Expect at most one open challenge per club to be genuinely enforced (inside
-- begin/rollback, a real club id if one exists, or skip if `club` is still
-- empty):
--   insert into "club_challenge" (club_id, name, target_type, target_value, deadline)
--     values ('<real club id>', 'Test A', 'distance', 100, now() + interval '30 days');
--   insert into "club_challenge" (club_id, name, target_type, target_value, deadline)
--     values ('<real club id>', 'Test B', 'distance', 200, now() + interval '30 days');
--   -- second insert => ERROR: duplicate key value violates unique constraint
--   -- "club_challenge_one_open_per_club_idx"
--
-- Expect at most one open membership stint per user per club to be genuinely
-- enforced:
--   insert into "club_membership_history" (club_id, user_id, joined_at)
--     values ('<real club id>', '<real user id>', now());
--   insert into "club_membership_history" (club_id, user_id, joined_at)
--     values ('<real club id>', '<real user id>', now());
--   -- second insert => ERROR: duplicate key value violates unique constraint
--   -- "club_membership_history_open_stint_idx"
