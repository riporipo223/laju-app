# ADR-0013: Append-only PointTransaction ledger with a separately precomputed leaderboard table

**Date**: 2026-09-10, extended for flag/reject/soft-delete handling through Round 7 (tech-spec.md §4 NFR, §2.4.1; database-api-spec.md §1)
**Status**: accepted
**Deciders**: Project lead

## Context

Points must support: full audit trail (why does a user have this total?), safe correction when a `flagged` run later resolves to `approved` or `rejected` (ADR-0008), and leaderboard reads fast enough for p95 < 300ms (tech-spec.md §4 NFR) against a growing history of every run ever submitted. A single mutable "current total points" column per user would satisfy none of these: no audit trail, no safe way to reverse a `rejected`-after-partial-award without ambiguity about what was reversed, and no way to serve fast ranked reads without scanning/aggregating history on every request.

## Decision

Two separate, purpose-built structures:
1. **`PointTransaction`**: an append-only ledger. Every point award is its own row; nothing is ever updated or deleted. A `rejected` override after a partial `flagged`-state award is corrected by writing a *new* row (`type: adjustment`, negative value) that nets the total to zero — never by mutating or removing the original row.
2. **`LeaderboardEntry`**: a separately precomputed, materialized table, rebuilt by a scheduled job (Vercel Cron, 15-minute interval — tech-spec.md's precompute freshness NFR) that aggregates the ledger into ranked rows per scope (global/kecamatan/kabupaten-kota/provinsi — **note 2026-09-22: regional scopes cancelled permanently, `global` is now the only scope this job will ever compute; product-spec.md §4.6. The ADR's decision is unaffected — precompute-over-live-aggregation stands on its own merits**). `GET /api/leaderboard` reads only this precomputed table, never aggregates the raw ledger live at request time. `flagged`-status runs are excluded from precompute until resolved; soft-deleted users (`deleted_at IS NOT NULL`) are excluded going forward, with `frozen_display_name` denormalized at write time so a past season's entries don't go blank once a user's live `display_name` is cleared.

## Alternatives Considered

### Alternative 1: Single mutable `total_points` column on `User`, updated in place
- **Pros**: Simplest possible model — no ledger, no precompute job.
- **Cons**: No audit trail (cannot answer "why does this user have 340 points" after the fact); a `flagged`→`rejected` reversal has no safe mechanical definition (subtract what, exactly, without a record of what was added); every leaderboard read would need either a live aggregation (too slow for p95 < 300ms at scale) or a second derived structure anyway — arriving back at needing a ledger, just without ever having built one.
- **Why not**: Fails the audit-trail requirement outright and doesn't actually avoid needing a second structure for leaderboard performance.

### Alternative 2: Live aggregation from `PointTransaction` on every leaderboard request, no separate precomputed table
- **Pros**: Leaderboard is always perfectly up to date, no staleness window, no cron job to run or monitor.
- **Cons**: Aggregating and ranking across a growing ledger, per scope, on every request does not meet the p95 < 300ms NFR at any meaningful scale — ranking queries (`GROUP BY`/window functions) over raw transaction history are the specific cost tech-spec.md's Postgres-over-Firestore ADR (ADR-0006) was chosen partly to make cheap, but "cheap" still isn't "free per request."
- **Why not**: Explicitly rejected by tech-spec.md's own performance NFR — the leaderboard is stated as deliberately **not** computed live from the raw transaction table at request time.

### Alternative 3: Mutate/delete ledger rows directly when a flagged run is later rejected
- **Pros**: Keeps the ledger's running total trivially correct without needing to reason about offsetting entries.
- **Cons**: Destroys the audit trail for exactly the runs that most need one — the disputed/flagged/rejected cases are precisely where a reviewer or the user themselves may need to see what was originally recorded and what was reversed and why.
- **Why not**: Violates the append-only guarantee the ledger exists to provide; tech-spec.md §4 NFR states explicitly the ledger is "tidak pernah di-update/delete."

## Consequences

### Positive
- Full audit trail and re-derivable point totals at any time, for any user, without ever having lost history — the explicit purpose stated in tech-spec.md §4 NFR.
- Leaderboard reads meet the p95 < 300ms NFR by construction, since they never touch the raw ledger at request time.
- The `flagged`-exclusion + `resolved_at`/precompute-rebuild interaction (ADR-0008, ADR-0010) composes cleanly with this model: a resolving run simply becomes eligible for the *next* precompute cycle, no special-case ledger surgery needed.
- Soft-deleted users' historical leaderboard entries remain legible (`frozen_display_name`) without needing a live join back to a `User` row that may have its display fields cleared.

### Negative
- Leaderboard freshness has an explicit staleness window (up to 15 minutes, tech-spec.md §4 NFR) — not real-time. A user's just-completed run will not appear in rankings instantly, only after the next precompute cycle.
- Two structures (ledger + materialized table) must be kept conceptually separate by every future contributor — writing points directly into `LeaderboardEntry`, or trying to "fix" a total by editing a `PointTransaction` row in place, would both be architecture violations that aren't obvious from the schema alone without this ADR.

### Risks
- Precompute job correctness (exclusion of `flagged`/soft-deleted rows, correct scope aggregation) is now a single shared point of failure for leaderboard accuracy across all scopes — a bug in the 15-minute cron job silently produces a wrong public leaderboard until caught, rather than each read recomputing independently. Mitigation: precompute **rebuilds** the table each cycle (not incremental patches), per database-api-spec.md §1, so a fixed job self-heals on its next run rather than accumulating drift.
