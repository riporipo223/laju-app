-- T2.17: one seeded active Season for initial development/testing (database-api-spec.md §2.5). Season
-- lifecycle transitions (upcoming -> active -> ended) are explicitly out of this task's scope (Fase 3,
-- T3.6) — this is a one-time data seed, not a mechanism. Guarded by WHERE NOT EXISTS so re-running this
-- migration (or an accidental replay) never creates a second active season.
insert into "season" (name, start_at, end_at, status)
select 'Season 1 — 2026', '2026-09-01T00:00:00Z', '2026-11-30T23:59:59Z', 'active'
where not exists (select 1 from "season" where status = 'active');
