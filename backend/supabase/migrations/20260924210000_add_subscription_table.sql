-- T4.20a — Premium: `subscription` table (product-spec.md §4.23, decided #2, AC6, AC14).
--
-- ============================================================================
-- APPLIED 2026-09-25. VERIFIED LIVE 2026-09-25: 2/4 checks passed, 2 blocked.
-- - table exists, schema-qualified (information_schema.tables): confirmed
-- - RLS enabled, schema-qualified (pg_class join pg_namespace): confirmed
-- - CHECK constraint rejection, and the append-only two-row-same-
--   original_transaction_id pattern: NOT verified — both need a real
--   user_id and an INSERT, which this session's write classifier blocked
--   (same class of block T4.15/T4.21's own trigger tests hit). Not claimed
--   passed. The CHECK constraint itself is a standard Postgres CHECK, low
--   risk but genuinely unexercised.
-- ============================================================================
--
-- Scope note: this is ONLY the schema (T4.20a). No backend verification logic
-- (T4.20b, blocked in full by the Apple Developer Program — see HANDOFF.md
-- §4) and no iOS StoreKit code (T4.20c) exist yet. Nothing writes to this
-- table until T4.20b ships.
--
-- Append-only ledger (ADR-0013), same pattern as `point_transaction`
-- (20260917162813_create_core_schema.sql) and `club_war` — a status change is
-- a new row, never an UPDATE (AC6). `original_transaction_id` identifies one
-- real-world Apple subscription across its rows; the current status is the
-- most recent row for that id (ordered by `created_at`).
--
-- `status` translates Apple's raw numeric statuses (App Store Server API,
-- product-spec.md §4.23 decided #9) into this repo's usual semantic-string
-- convention (matches `club_war.status`, `run.status`, etc. — every other
-- status column here is a readable word, never a raw provider code):
--   Apple 1 (active)         -> 'active'
--   Apple 2 (expired)        -> 'expired'
--   Apple 3 (billing retry)  -> 'billing_retry'
--   Apple 4 (grace period)   -> 'grace_period'
--   Apple 5 (revoked)        -> 'revoked'
-- AC10: 'active', 'billing_retry' and 'grace_period' count as Premium;
-- 'expired' and 'revoked' do not. That comparison is T4.20b's job, not
-- this migration's — this table only needs to be able to store the value.
--
-- `expires_at` is nullable: a `revoked` row may carry no meaningful
-- expiration (Apple's revocation data is a `revocationDate`, not always an
-- `expiresDate`), and T4.20b's exact mapping isn't built yet to confirm
-- this is never needed. Tightening to NOT NULL later is easy; a wrong NOT
-- NULL now, discovered only once real Apple payloads exist, is not — flagged
-- here for the review gate to confirm or override before this is applied.
--
-- `user_id` is NOT NULL (settled 2026-09-23 with decided #13 / AC14):
-- deleting an account never touches `subscription` rows — the `user` row
-- they point to is anonymized by T2.22 instead, exactly like
-- `point_transaction.user_id` today. No account-deletion code change needed
-- for this table (verified: `backend/lib/account-deletion.ts` does not
-- reference `subscription` and does not need to).

begin;

-- ============================================================
-- subscription
-- ============================================================
create table "subscription" (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references "user" (id),
  original_transaction_id text not null,
  product_id text not null,
  status text not null check (status in ('active', 'expired', 'billing_retry', 'grace_period', 'revoked')),
  expires_at timestamptz,
  environment text not null check (environment in ('sandbox', 'production')),
  created_at timestamptz not null default now()
);

-- Supports AC6's "current status = most recent row for this
-- original_transaction_id" read pattern.
create index "subscription_original_transaction_id_created_at_idx"
  on "subscription" (original_transaction_id, created_at desc);

-- Supports the Premium check read pattern (T4.20b, §4.19 Premium Club,
-- §4.5 AC4): "does this user have an active subscription."
create index "subscription_user_id_idx" on "subscription" (user_id);

-- ============================================================
-- RLS — matches 20260919150457_enable_rls_deny_anon.sql's established
-- policy for every table in this schema: RLS enabled, zero grants to
-- anon/authenticated. All access goes through the Vercel API's service_role
-- key, which bypasses RLS and scopes queries in code.
-- ============================================================
alter table "subscription" enable row level security;

revoke all on table "subscription" from anon, authenticated;

commit;

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- begin;
--
-- drop table if exists "subscription";
--
-- commit;
--
-- Note: pure rollback of an empty, newly-created table — no data-loss risk,
-- since nothing has ever written to this table until T4.20b exists.

-- ============================================================================
-- VERIFICATION (run after applying — required real evidence, same discipline
-- as T4.2a)
-- ============================================================================
-- Expect 1 row:
--   select table_name from information_schema.tables
--    where table_schema = 'public' and table_name = 'subscription';
--
-- Expect rowsecurity = true — schema-qualified: Supabase's own `realtime`
-- schema has an unrelated internal table also named `subscription`
-- (confirmed live while verifying this migration), so a bare `relname`
-- match returns two rows, not one:
--   select c.relname, c.relrowsecurity from pg_class c
--     join pg_namespace n on n.oid = c.relnamespace
--    where c.relname = 'subscription' and n.nspname = 'public';
--
-- Expect the status CHECK to reject an invalid value:
--   insert into "subscription"
--     (user_id, original_transaction_id, product_id, status, environment)
--   values ('<real-user-id>', 'test-txn-1', 'com.designbyripo.laju.premium.monthly', 'bogus', 'sandbox');
--   -- expect: ERROR: new row for relation "subscription" violates check constraint
--   -- "subscription_status_check"
--
-- Expect a valid row to insert cleanly, and a second row for the same
-- original_transaction_id to represent the append-only status-change pattern
-- (AC6 — never an UPDATE):
--   insert into "subscription"
--     (user_id, original_transaction_id, product_id, status, expires_at, environment)
--   values ('<real-user-id>', 'test-txn-1', 'com.designbyripo.laju.premium.monthly', 'active',
--           now() + interval '30 days', 'sandbox');
--   insert into "subscription"
--     (user_id, original_transaction_id, product_id, status, expires_at, environment)
--   values ('<real-user-id>', 'test-txn-1', 'com.designbyripo.laju.premium.monthly', 'expired',
--           now() - interval '1 day', 'sandbox');
--   -- expect: 2 rows for original_transaction_id = 'test-txn-1'; the most recent
--   -- (by created_at) has status = 'expired' — that is "current status" per AC6.
