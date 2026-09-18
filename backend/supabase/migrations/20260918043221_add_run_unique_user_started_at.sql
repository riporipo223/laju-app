-- T2.12d: duplicate-submission idempotency (database-api-spec.md §3). This is the actual enforcement
-- mechanism — the application-level "check first, then insert" in route.ts has a TOCTOU race between two
-- concurrent identical submissions; only a DB-level constraint closes that gap (Postgres returns error code
-- 23505 on the losing insert, which route.ts catches and turns into "return the winner's result" instead
-- of a 500). NULL started_at rows are NOT deduplicated by this constraint — Postgres treats every NULL as
-- distinct under a UNIQUE constraint — but the client always sends started_at (database-api-spec.md §2.2's
-- request shape), so this is an accepted, not-closed-here edge case, same as the task's own scope note.
alter table "run"
  add constraint "run_user_id_started_at_key" unique ("user_id", "started_at");
