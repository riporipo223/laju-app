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

-- ============================================================
-- V4 — cross-user posting rejected
-- Expect error containing: "does not belong to user"
-- ============================================================
begin;
with ua as (
  insert into "user" (email, username, display_name)
  values ('qa-test-v4a@test.local','qa-test-v4a','QA Test V4A')
  returning id
), ub as (
  insert into "user" (email, username, display_name)
  values ('qa-test-v4b@test.local','qa-test-v4b','QA Test V4B')
  returning id
), rb as (
  insert into "run" (user_id, status)
  select id, 'validated' from ub
  returning id
)
insert into "social_post" (user_id, run_id)
select ua.id, rb.id from ua, rb;
-- (no commit)

-- ============================================================
-- V5 — double-like rejected
-- Expect error containing: "duplicate key value violates unique constraint"
-- ============================================================
begin;
with u as (
  insert into "user" (email, username, display_name)
  values ('qa-test-v5@test.local','qa-test-v5','QA Test V5')
  returning id
), r as (
  insert into "run" (user_id, status)
  select id, 'validated' from u
  returning id, user_id
), p as (
  insert into "social_post" (user_id, run_id)
  select user_id, id from r
  returning id, user_id
), like1 as (
  insert into "social_post_like" (post_id, user_id)
  select id, user_id from p
  returning post_id, user_id
)
insert into "social_post_like" (post_id, user_id)
select post_id, user_id from like1;
-- (no commit — second insert should fail with duplicate key error)

-- ============================================================
-- V6 — cascade delete
-- Run all statements below as ONE block (same transaction).
-- Expect: count_before = 1, count_after = 0
-- ============================================================
begin;
-- temp table holds post_id across statements — after DELETE, "social_post"
-- no longer has the row, so re-deriving post_id FROM social_post post-delete
-- would silently yield NULL and make count_after false-positive 0.
create temp table qa_v6_ctx (post_id uuid, user_id uuid) on commit drop;

with u as (
  insert into "user" (email, username, display_name)
  values ('qa-test-v6@test.local','qa-test-v6','QA Test V6')
  returning id
), r as (
  insert into "run" (user_id, status)
  select id, 'validated' from u
  returning id, user_id
), p as (
  insert into "social_post" (user_id, run_id)
  select user_id, id from r
  returning id, user_id
)
insert into qa_v6_ctx select id, user_id from p;

insert into "social_post_like" (post_id, user_id)
select post_id, user_id from qa_v6_ctx;

select count(*) as count_before from "social_post_like"
 where post_id = (select post_id from qa_v6_ctx);

delete from "social_post" where id = (select post_id from qa_v6_ctx);

select count(*) as count_after from "social_post_like"
 where post_id = (select post_id from qa_v6_ctx);
-- (no commit)
