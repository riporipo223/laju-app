-- T4.15 social_feed_schema — V3-V6 trigger verification.
-- Run EACH block separately in Supabase SQL Editor. Do NOT add "commit;" —
-- every block ends on purpose without commit so Postgres auto-rolls-back
-- when the editor's connection closes. Zero rows persist after any block.
-- Paste back the JSON/error output of each block.

-- ============================================================
-- V3 — flagged run rejected
-- Expect error containing: "has status flagged"
-- ============================================================
begin;
with u as (
  insert into "user" (email, username, display_name)
  values ('qa-test-v3@test.local','qa-test-v3','QA Test V3')
  returning id
), r as (
  insert into "run" (user_id, status)
  select id, 'flagged' from u
  returning id, user_id
)
insert into "social_post" (user_id, run_id)
select user_id, id from r;
-- (no commit — let editor roll it back, or run: rollback;)
