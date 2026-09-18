-- T2.2: core schema for all 6 entities in database-api-spec.md §1's ERD.
-- Club is deliberately NOT created (Won't/backlog, product-spec.md) —
-- "user".club_id is a reserved nullable FK-shaped column with no FK
-- constraint, since there is no table for it to reference yet.

create extension if not exists "pgcrypto";

-- ============================================================
-- season
-- ============================================================
create table "season" (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  status text not null check (status in ('upcoming', 'active', 'ended')),
  created_at timestamptz not null default now()
);

-- ============================================================
-- user
-- ============================================================
-- auth_user_id deliberately carries NO foreign key to auth.users
-- (2026-09-13, Round 7 finding B7-9): a standard FK here would either
-- CASCADE (physically deleting this row when the Auth identity is
-- deleted via the Admin API, defeating soft-delete) or RESTRICT (blocking
-- the Admin API delete entirely). Decoupling is enforced by omission —
-- the application looks up this column, but Postgres enforces nothing
-- about its relationship to auth.users.
create table "user" (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique,
  email text unique,
  username text,
  display_name text,
  avatar_url text,
  region_kecamatan text,
  region_kabupaten_kota text,
  region_provinsi text,
  total_points integer not null default 0,
  current_level integer not null default 1,
  trust_score double precision not null default 1.0,
  club_id uuid, -- reserved, nullable, no FK — Club table not built in v1
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ============================================================
-- run
-- ============================================================
create table "run" (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references "user" (id),
  started_at timestamptz,
  ended_at timestamptz,
  distance_meters double precision,
  duration_seconds integer,
  avg_pace_sec_per_km integer,
  gps_route jsonb,
  status text not null check (status in ('validated', 'flagged', 'approved', 'rejected')),
  flag_confidence text check (flag_confidence in ('low', 'high')),
  anomaly_flags jsonb not null default '[]'::jsonb,
  estimated_points integer,
  final_points_awarded integer,
  resolved_at timestamptz,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- database-api-spec.md §1: "set at insert and re-touched by a DB-level
-- trigger (not application code) on any change to
-- status/flag_confidence/final_points_awarded/resolved_at, so no writer
-- can forget it." A trigger, not an app-layer ORM hook, so a raw SQL
-- writer (a migration, a manual fix, a different future service) cannot
-- silently bypass it.
create function "run_touch_updated_at"()
returns trigger
language plpgsql
as $$
begin
  if
    new.status is distinct from old.status
    or new.flag_confidence is distinct from old.flag_confidence
    or new.final_points_awarded is distinct from old.final_points_awarded
    or new.resolved_at is distinct from old.resolved_at
  then
    new.updated_at = now();
  end if;
  return new;
end;
$$;

create trigger "run_updated_at_trigger"
before update on "run"
for each row
execute function "run_touch_updated_at"();

-- The filter column for GET /api/runs?since= (T2.14c, §2.2b).
create index "run_user_id_updated_at_idx" on "run" (user_id, updated_at);

-- ============================================================
-- point_transaction
-- ============================================================
-- Append-only ledger (ADR-0013) — rows are never UPDATEd or DELETEd by
-- application code; T2.2 does not add DB-level write restrictions
-- (e.g. REVOKE), since that is out of this task's scope.
create table "point_transaction" (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references "user" (id),
  run_id uuid references "run" (id), -- nullable: non-run grants (adjustment)
  season_id uuid not null references "season" (id),
  amount integer not null,
  type text not null check (type in ('run', 'streak_bonus', 'adjustment')),
  created_at timestamptz not null default now()
);

-- ============================================================
-- leaderboard_scope
-- ============================================================
-- scope_id uses the 'GLOBAL' sentinel for scope_type='global' (never
-- NULL — the composite PK cannot hold NULL in Postgres, §1's "Why
-- scope_id='GLOBAL'" note).
create table "leaderboard_scope" (
  season_id uuid not null references "season" (id),
  scope_type text not null check (scope_type in ('global', 'kecamatan', 'kabupaten_kota', 'provinsi')),
  scope_id text not null,
  user_count integer not null default 0,
  insufficient_data boolean not null default false,
  computed_at timestamptz not null default now(),
  primary key (season_id, scope_type, scope_id)
);

-- ============================================================
-- leaderboard_entry
-- ============================================================
create table "leaderboard_entry" (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references "season" (id),
  scope_type text not null check (scope_type in ('global', 'kecamatan', 'kabupaten_kota', 'provinsi')),
  scope_id text not null,
  user_id uuid not null references "user" (id),
  frozen_display_name text, -- denormalized at precompute time, NOT a live join (§1, B7-12)
  points integer not null,
  rank integer not null,
  computed_at timestamptz not null default now()
);
