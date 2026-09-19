-- Security fix found in the Fase 2 audit (2026-09-19; security-review.md SEC-11 had flagged RLS as never discussed).
--
-- Before this migration every table in `public` had row level security OFF and full SELECT/INSERT/UPDATE/DELETE
-- granted to the `anon` and `authenticated` roles (Supabase's default). The `anon` key ships inside the iOS app
-- and is committed to the (public) repo — by design it is not a secret — so anyone could read or rewrite the
-- whole database over PostgREST with a single curl: other users' emails and GPS routes, points, trust scores,
-- the ledger, the leaderboard.
--
-- The architecture never needed that door: the mobile app talks to Supabase only for *Auth*; every data access
-- goes through the Vercel API, which uses the `service_role` key (bypasses RLS) and scopes each query to the
-- caller in code. So the right policy set is EMPTY: RLS enabled with no policies = deny everything to `anon` and
-- `authenticated`. The explicit REVOKEs are belt-and-braces (a table without RLS but without grants is also
-- closed), and the default-privilege change stops future tables from silently re-opening the same hole.
--
-- If a table ever needs direct client access, add a narrowly-scoped policy for it deliberately — do not
-- re-grant broadly.

alter table "user" enable row level security;
alter table run enable row level security;
alter table point_transaction enable row level security;
alter table season enable row level security;
alter table leaderboard_entry enable row level security;
alter table leaderboard_scope enable row level security;

revoke all on table "user", run, point_transaction, season, leaderboard_entry, leaderboard_scope
  from anon, authenticated;

alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
