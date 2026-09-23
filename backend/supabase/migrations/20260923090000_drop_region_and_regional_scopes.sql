-- Task B — drop region hierarchy and regional leaderboard scopes
--
-- Context: Local Leaderboard was cancelled permanently 2026-09-22 (PM sign-off,
-- product-spec.md §4.6) and decision D1 ("region mandatory in v1") was reversed the
-- same day (product-spec.md §4.1). Region was collected solely to prepare data for
-- the Local Leaderboard; with that feature gone there is nothing left to prepare for.
-- Replacement: leaderboard visibility is gated client-side on granted location
-- permission (product-spec.md §4.5 AC5) — no place name, no reverse geocoding, and
-- no administrative hierarchy is stored anywhere.
--
-- ============================================================================
-- APPLIED 2026-09-23 — this migration has already been run against production.
-- ============================================================================
-- Verified: 0 region_* columns remain on `user`, both leaderboard tables show only
-- `global` scope_type, the new check constraint genuinely rejects a regional insert
-- (see the Verification block below — these are the exact queries used). A
-- pre-migration snapshot (`user_region_backup_20260923`) was taken before applying.
-- Fallout in code/tests/policy that depended on the pre-migration schema was found
-- and fixed in a follow-up commit (`ed625c6`) — see that commit's message for detail.
--
-- The banner and rollback/verification sections below are kept as-is, unmodified,
-- as the historical record of the real expand→migrate→verify→contract sequence this
-- migration went through — this file is not re-run, only read for reference now.
--
-- ---------------------------------------------------------------------------
-- Original pre-apply banner (kept verbatim below for the record):
-- ---------------------------------------------------------------------------
-- DO NOT RUN THIS UNTIL TASK C IS DEPLOYED TO PRODUCTION.
--
-- This is the CONTRACT step of an expand→migrate→verify→contract sequence. Until
-- Task C's backend change is live on `main`, the deployed code still selects these
-- columns in `lib/auth.ts`'s shared auth path — dropping them first makes PostgREST
-- reject that SELECT and takes down EVERY authenticated endpoint, not just profile
-- completion. Order is: Task C ships → deploy confirmed live → then apply this.
--
-- Destructive and irreversible for data: the three region columns are free text with
-- no backup elsewhere. The rollback section below restores the SCHEMA, not the VALUES.
-- If the values matter, snapshot them before applying:
--     create table user_region_backup_20260923 as
--       select id, region_kecamatan, region_kabupaten_kota, region_provinsi from "user";
-- (No such snapshot is taken automatically — the data is being deliberately discarded.)

begin;

-- ---------------------------------------------------------------------------
-- 1. Drop the region hierarchy from `user`
-- ---------------------------------------------------------------------------
alter table "user" drop column if exists region_kecamatan;
alter table "user" drop column if exists region_kabupaten_kota;
alter table "user" drop column if exists region_provinsi;

-- ---------------------------------------------------------------------------
-- 2. Remove regional scope_type values — `global` becomes the only legal scope
-- ---------------------------------------------------------------------------
-- Defensive: v1 only ever wrote `global` rows (T2.18 precompute), so these deletes
-- are expected to affect 0 rows. They exist so the constraint swap below cannot fail
-- on unexpected leftover data from manual testing.
delete from "leaderboard_entry" where scope_type <> 'global';
delete from "leaderboard_scope" where scope_type <> 'global';

alter table "leaderboard_scope" drop constraint if exists leaderboard_scope_scope_type_check;
alter table "leaderboard_scope"
  add constraint leaderboard_scope_scope_type_check check (scope_type = 'global');

alter table "leaderboard_entry" drop constraint if exists leaderboard_entry_scope_type_check;
alter table "leaderboard_entry"
  add constraint leaderboard_entry_scope_type_check check (scope_type = 'global');

commit;

-- ============================================================================
-- ROLLBACK (restores schema shape, NOT the discarded region values)
-- ============================================================================
-- begin;
--
-- alter table "user" add column if not exists region_kecamatan text;
-- alter table "user" add column if not exists region_kabupaten_kota text;
-- alter table "user" add column if not exists region_provinsi text;
--
-- alter table "leaderboard_scope" drop constraint if exists leaderboard_scope_scope_type_check;
-- alter table "leaderboard_scope"
--   add constraint leaderboard_scope_scope_type_check
--   check (scope_type in ('global', 'kecamatan', 'kabupaten_kota', 'provinsi'));
--
-- alter table "leaderboard_entry" drop constraint if exists leaderboard_entry_scope_type_check;
-- alter table "leaderboard_entry"
--   add constraint leaderboard_entry_scope_type_check
--   check (scope_type in ('global', 'kecamatan', 'kabupaten_kota', 'provinsi'));
--
-- commit;
--
-- Note: rolling back the schema does NOT restore region values. Re-populating them
-- would require the optional snapshot table above, or re-onboarding every user.

-- ============================================================================
-- VERIFICATION (run after applying — this is Task B's required real evidence)
-- ============================================================================
-- Expect 0 rows:
--   select column_name from information_schema.columns
--    where table_name = 'user' and column_name like 'region_%';
--
-- Expect only 'global':
--   select distinct scope_type from "leaderboard_scope";
--   select distinct scope_type from "leaderboard_entry";
--
-- Expect the new constraint to reject a regional value:
--   insert into "leaderboard_scope" (season_id, scope_type, scope_id)
--     values ((select id from "season" limit 1), 'kecamatan', 'X');
--   -- => ERROR: new row violates check constraint "leaderboard_scope_scope_type_check"
