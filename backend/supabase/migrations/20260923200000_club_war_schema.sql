-- T4.2a — Club War data model (product-spec.md §4.19, AC1-AC9).
--
-- ============================================================================
-- APPLIED 2026-09-24 to production. Real evidence (all 5 checks from this
-- file's own VERIFICATION section below, run for real):
--   - 5 tables exist: club, club_member, club_war, club_war_club,
--     club_war_participant (information_schema.tables).
--   - RLS enabled (relrowsecurity = true) on all 5 (pg_class).
--   - win_reason CHECK constraint includes 'forfeit_premium_lapse'
--     (pg_get_constraintdef).
--   - Max-3-clubs trigger genuinely rejected a 4th club-war-club insert:
--     "club_war ... already has 3 clubs entered (max per §4.19 AC1)".
--   - One-open-war trigger genuinely rejected a club already in a
--     pending/active war: "club ... is already in a pending or active war
--     (§4.19 AC14)".
--   - One-club-per-user PK genuinely rejected a second club_member row for
--     the same real user_id: "duplicate key value violates unique
--     constraint club_member_pkey".
-- All constraint-rejection tests ran inside begin/rollback against a real
-- user id; zero rows left behind (verified: club/club_member/club_war all
-- count 0 immediately after).
-- ============================================================================
--
-- AMENDED 2026-09-24, still before any apply (PM decisions): `win_reason` also accepts
-- 'forfeit_premium_lapse' (§4.19 AC10), and a trigger enforces one pending/active war per club
-- (§4.19 AC14). Edited in place rather than as a follow-up migration because nothing has run it yet.
--
-- LEARNED FROM TASK B: that migration's own "DO NOT RUN" banner went stale after
-- being applied for real and had to be corrected in a follow-up commit
-- (a81bc01/ed625c6). If this migration is actually applied, THIS BANNER MUST BE
-- UPDATED to say so, with evidence (verification queries below run for real) —
-- do not leave it claiming "not yet applied" once it has been.
--
-- ============================================================================
-- Scope note: this migration builds a MINIMAL `club`/`club_member` stub, not the
-- full Club feature (T4.1, "data model + UI", is separately scoped and not yet
-- built at all). T4.2 (Club War) formally depends on T4.1 per phase-4-backlog.md,
-- but T4.1 has no schema of its own yet and Club War cannot exist without SOME
-- club table to reference — so this migration builds only the columns Club War
-- itself needs (identity for display/FK, ownership role for the "self-serve by
-- owner/admin" rule in §4.19). No description, privacy/visibility, invite_code,
-- or join-request flow — those are T4.1's own scope (see user-flow.md §2.6 for
-- the unreconciled draft covering them) and are deliberately NOT invented here.
-- T4.1, when scoped, will most likely ALTER this table to add its own columns,
-- not create a new one.
-- ============================================================================

begin;

-- ============================================================
-- club (minimal stub — see scope note above)
-- ============================================================
create table "club" (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

-- ============================================================
-- club_member
-- ============================================================
-- Sole source of truth for club membership. `user.club_id` (reserved nullable,
-- no FK, since T2.2 / 20260917162813_create_core_schema.sql) is DELIBERATELY
-- NOT promoted to a real FK or wired up here — see this migration's report for
-- the rationale (a denormalized column duplicating this table would be a second
-- source of truth to keep in sync, for no requirement that needs it). Its
-- eventual disposition (repurposed as a fast-lookup cache, or formally dropped)
-- is left to T4.1, not decided here.
--
-- user_id is the PRIMARY KEY (not a surrogate id) to enforce "one club per
-- user" at the database level. First inferred from the single-FK-column shape
-- of `user.club_id`; CONFIRMED as a deliberate PM decision 2026-09-23
-- (product-spec.md §4.19): it prevents cross-club double-counting in
-- Participation Rate and in this war snapshot.
--
-- No 'pending' / join-request state — this table holds only CONFIRMED members.
-- T4.1's own join/invite flow (user-flow.md §2.6 draft: "request join atau
-- langsung masuk") may need a separate request table or an added status value
-- when it's actually scoped; not decided here.
create table "club_member" (
  user_id uuid primary key references "user" (id),
  club_id uuid not null references "club" (id),
  role text not null check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now()
);

create index "club_member_club_id_idx" on "club_member" (club_id);

-- ============================================================
-- club_war
-- ============================================================
-- Status has TWO separate terminal paths, per §4.19 AC7 — deliberately not
-- collapsed into one generic 'cancelled' status:
--   pending -> active -> ended       (a real match happened; produces a
--                                      recorded win/loss outcome)
--   pending -> dissolved             (declined or 24h timeout; NO win/loss
--                                      outcome for anyone, as if it never
--                                      happened)
-- winner_club_id is on this table as a convenience denormalization of what
-- club_war_club's own per-club `outcome` column already states authoritatively;
-- kept nullable, set only when status = 'ended'.
create table "club_war" (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'pending' check (status in ('pending', 'active', 'dissolved', 'ended')),
  challenge_sent_at timestamptz not null default now(),
  -- All invited clubs are assumed invited atomically in one challenge action
  -- (AC1's framing: one challenge names 1-2 invited clubs, not serial separate
  -- invites) — a single deadline for the whole challenge is therefore correct,
  -- not one deadline per invited club.
  accept_deadline_at timestamptz not null default (now() + interval '24 hours'),
  started_at timestamptz, -- set when status -> active (every invited club accepted)
  ended_at timestamptz,   -- set when status -> ended (48h window elapsed or forfeit)
  winner_club_id uuid references "club" (id), -- nullable; set only when status = 'ended'
  -- 'forfeit_premium_lapse' added 2026-09-24, before this migration was ever applied (§4.19 AC10):
  -- the backend (T4.2b) records it when the inviter's owner has lost Premium at the 48h check.
  win_reason text check (win_reason in ('participation_rate', 'tie_break', 'forfeit_inactivity', 'forfeit_premium_lapse')),
  created_at timestamptz not null default now(),
  constraint club_war_winner_only_when_ended
    check (status = 'ended' or (winner_club_id is null and win_reason is null))
);

-- Drives T4.2b's dissolve-on-timeout job (mirrors the existing pg_cron
-- `advance-seasons` pattern, 20260921180000_season_lifecycle.sql) — a partial
-- index so the scan only ever touches wars that could still time out.
create index "club_war_pending_deadline_idx" on "club_war" (accept_deadline_at) where status = 'pending';

-- ============================================================
-- club_war_club
-- ============================================================
-- One row per club entered in a war (2-3 rows per war: 1 inviter + 1-2
-- invited). Tracks BOTH the Phase 1 invite-acceptance state AND, once the war
-- reaches Phase 2/ended, that club's own Participation Rate + win/loss outcome
-- for that war. This is the unit of data §4.20 Section 2's Club War Record
-- precompute aggregates from.
--
-- The dissolved-vs-ended distinction is queryable directly: a dissolved war's
-- rows never get `outcome` populated (stays NULL forever, since AC7 says no
-- war means no outcome for anyone), so the Club War Record precompute filters
-- `join club_war on club_war.status = 'ended'` and gets a correct answer by
-- construction, not by convention.
create table "club_war_club" (
  club_war_id uuid not null references "club_war" (id),
  club_id uuid not null references "club" (id),
  role text not null check (role in ('inviter', 'invited')),
  invite_status text not null default 'pending' check (invite_status in ('pending', 'accepted', 'declined')),
  responded_at timestamptz, -- nullable; set on explicit accept/decline, stays null on timeout-dissolve
  participation_rate numeric, -- nullable; set only once the war reaches 'ended'
  outcome text check (outcome in ('win', 'loss')), -- nullable; set only once 'ended' — see comment above
  primary key (club_war_id, club_id),
  constraint club_war_club_outcome_needs_rate
    check (outcome is null or participation_rate is not null)
);

create index "club_war_club_club_id_idx" on "club_war_club" (club_id);

-- Exactly one 'inviter' row per war — a structural invariant, not a business
-- rule that could plausibly change, so enforced here rather than left to the
-- API layer (matches this repo's stated preference for DB-level invariants,
-- e.g. season_single_active in 20260921180000_season_lifecycle.sql).
create unique index "club_war_club_one_inviter_idx" on "club_war_club" (club_war_id) where role = 'inviter';

-- AC1: max 3 clubs per war (1 inviter + up to 2 invited). A CHECK constraint
-- cannot count sibling rows, so this is a trigger — the same DB-level-guarantee
-- philosophy as season_single_active, applied where a plain constraint can't
-- reach.
create function "club_war_club_enforce_max_three"()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from "club_war_club" where club_war_id = new.club_war_id) >= 3 then
    raise exception 'club_war % already has 3 clubs entered (max per §4.19 AC1)', new.club_war_id;
  end if;
  return new;
end;
$$;

create trigger "club_war_club_max_three_trigger"
before insert on "club_war_club"
for each row
execute function "club_war_club_enforce_max_three"();

-- §4.19 AC14 (added 2026-09-24, before this migration was ever applied): a club is in at most one
-- pending-or-active war at a time. The backend checks this first; this trigger is the backstop for
-- two challenges racing each other. A partial unique index can't express it (the status lives on
-- `club_war`, not on this table), so it's a trigger, serialized per club with an advisory lock so
-- two concurrent inserts for the same club can't both pass the check.
create function "club_war_club_enforce_one_open_war"()
returns trigger
language plpgsql
as $$
begin
  perform pg_advisory_xact_lock(hashtext('club_war_open:' || new.club_id::text));
  if exists (
    select 1
    from "club_war_club" cwc
    join "club_war" cw on cw.id = cwc.club_war_id
    where cwc.club_id = new.club_id
      and cwc.club_war_id <> new.club_war_id
      and cw.status in ('pending', 'active')
  ) then
    raise exception 'club % is already in a pending or active war (§4.19 AC14)', new.club_id;
  end if;
  return new;
end;
$$;

create trigger "club_war_club_one_open_war_trigger"
before insert on "club_war_club"
for each row
execute function "club_war_club_enforce_one_open_war"();

-- ============================================================
-- club_war_participant
-- ============================================================
-- Frozen snapshot of which users count toward a club's Participation Rate for
-- ONE specific war, captured once at Phase 2 start (the moment every invited
-- club has accepted and the 48-hour window begins) — NOT a live join against
-- club_member's current state.
--
-- This exists specifically so the war's outcome is immune to membership
-- changes that happen mid-war or after it ends (a club's live roster can keep
-- changing; a past war's recorded result must not).
--
-- Policy DECIDED 2026-09-23 (PM, product-spec.md §4.19 AC11): a member who
-- leaves their club after the war went active STILL COUNTS for that war. This
-- snapshot is final for the war and is never edited when someone leaves. (Was
-- flagged "genuinely open" when this file was first written — corrected here,
-- comment-only, before the migration has ever been applied.)
create table "club_war_participant" (
  club_war_id uuid not null references "club_war" (id),
  club_id uuid not null references "club" (id),
  user_id uuid not null references "user" (id),
  snapshotted_at timestamptz not null default now(),
  primary key (club_war_id, club_id, user_id)
);

-- ============================================================
-- RLS — matches 20260919150457_enable_rls_deny_anon.sql's established
-- policy for every table in this schema: RLS enabled, zero grants to
-- anon/authenticated. All access goes through the Vercel API's service_role
-- key, which bypasses RLS and scopes queries in code — the same reasoning
-- that migration documented, applied to these 5 new tables so they don't
-- silently reopen the hole SEC-11 closed.
-- ============================================================
alter table "club" enable row level security;
alter table "club_member" enable row level security;
alter table "club_war" enable row level security;
alter table "club_war_club" enable row level security;
alter table "club_war_participant" enable row level security;

revoke all on table "club", "club_member", "club_war", "club_war_club", "club_war_participant"
  from anon, authenticated;

commit;

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- begin;
--
-- drop trigger if exists "club_war_club_one_open_war_trigger" on "club_war_club";
-- drop function if exists "club_war_club_enforce_one_open_war"();
-- drop trigger if exists "club_war_club_max_three_trigger" on "club_war_club";
-- drop function if exists "club_war_club_enforce_max_three"();
-- drop table if exists "club_war_participant";
-- drop table if exists "club_war_club";
-- drop table if exists "club_war";
-- drop table if exists "club_member";
-- drop table if exists "club";
--
-- commit;
--
-- Note: this is a pure rollback of empty, newly-created tables — no data-loss
-- risk analogous to Task B's region-column drop, since nothing has ever
-- written to these tables yet (they don't exist until this migration runs).

-- ============================================================================
-- VERIFICATION (run after applying — required real evidence, same discipline
-- as Task B)
-- ============================================================================
-- Expect 5 rows:
--   select table_name from information_schema.tables
--    where table_schema = 'public'
--      and table_name in ('club', 'club_member', 'club_war', 'club_war_club', 'club_war_participant');
--
-- Expect rowsecurity = true for all 5:
--   select relname, relrowsecurity from pg_class
--    where relname in ('club', 'club_member', 'club_war', 'club_war_club', 'club_war_participant');
--
-- Expect the max-3-clubs trigger to genuinely reject a 4th club (run inside a
-- transaction you roll back, not against real data):
--   insert into "club_war" (id) values (gen_random_uuid()) returning id;
--   -- then insert 3 club_war_club rows for that id with 3 distinct real club
--   -- ids, then attempt a 4th -- expect:
--   -- ERROR: club_war ... already has 3 clubs entered (max per §4.19 AC1)
--
-- Expect a club already in a pending/active war to be refused a second one (§4.19 AC14):
--   -- create war W1 with club X (pending), then insert a club_war_club row for club X into a
--   -- different war W2 -- expect:
--   -- ERROR: club ... is already in a pending or active war (§4.19 AC14)
--
-- Expect win_reason to accept the Premium-lapse forfeit:
--   select pg_get_constraintdef(oid) from pg_constraint where conname = 'club_war_win_reason_check';
--   -- => includes 'forfeit_premium_lapse'
--
-- Expect one-club-per-user to genuinely reject a second row for the same user:
--   insert into "club_member" (user_id, club_id, role) values ('<real-user-id>', '<club-a>', 'member');
--   insert into "club_member" (user_id, club_id, role) values ('<real-user-id>', '<club-b>', 'member');
--   -- second insert => ERROR: duplicate key value violates unique constraint "club_member_pkey"
