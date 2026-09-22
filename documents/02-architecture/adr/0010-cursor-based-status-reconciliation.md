# ADR-0010: Cursor-based status reconciliation (server-issued cursor, ASC + has_more)

**Date**: 2026-09-13 — redesigned after 4 rounds of incremental patching (database-api-spec.md §2.2b, tech-spec.md §3 step 7)
**Status**: accepted
**Deciders**: Project lead

## Context

A `flagged` run's later resolution (LOW confidence auto-approves up to 48h afterward; HIGH confidence resolves at an arbitrary later time via manual override) happens *after* the run is already synced — the initial `POST /api/runs` response cannot carry it (tech-spec.md §2.4.1). The client needs a way to learn about this later, asynchronously. This design went through four rounds of audit finding "the next missing piece" each time a narrower fix was applied (endpoint → filter column → local schema → gate wiring) before being redesigned as one coherent unit. Two specific bugs were found and rejected during that process: filtering on `resolved_at` (which is `null` for any still-`flagged` run, so it would never surface the transition *into* `flagged`), and an earlier draft's `DESC` ordering with `server_time` as the next cursor (which silently skips older, still-undrained rows when a batch is capped).

## Decision

`GET /api/runs?since=<server-issued timestamp>` filters on `Run.updated_at` (touched by a DB-level trigger on any change to `status`/`flag_confidence`/`final_points_awarded`/`resolved_at`) — never `resolved_at`. Results are capped at 200 rows, ordered `updated_at` **ASC** (oldest-changed-first), with `has_more: true` when the cap is hit. The client persists the cursor for its next call as:
- **`server_time`** (from the response) when `has_more: false` — the window is fully drained.
- **The last returned row's `updated_at`** when `has_more: true` — using `server_time` here would skip everything still undrained.

Never a device-local timestamp, on the first call or any later one — the very first call (no cursor persisted yet) omits `since` entirely, and the server defaults to a `now() - 90 days` lookback. The client-side loop (T2.14d) only calls this endpoint when it holds at least one locally-flagged run, respects a ≥15-minute-since-last-attempt cadence floor (persisted across restarts via `sync_meta.last_reconcile_attempt_at`), and drains a `has_more: true` response with immediate follow-up calls before waiting for the next cycle — breaking the drain loop once a follow-up call returns no row newer than the current cursor (handles the case where ≥200 rows share one identical `updated_at`).

## Alternatives Considered

### Alternative 1: Filter on `resolved_at` instead of `updated_at`
- **Pros**: Semantically closer to "give me runs that finished resolving."
- **Cons**: `resolved_at` is `null` for any run still `flagged` — a client would never learn a run *transitioned into* `flagged` in the first place if it wasn't already watching for that specific run some other way, and would definitely never see a HIGH-confidence run that's been `flagged` for a long time with no resolution yet.
- **Why not**: Structurally cannot surface the in-progress state, only the terminal one — misses exactly the case (a long-pending HIGH-confidence flag) the endpoint most needs to report on.

### Alternative 2: `DESC` ordering with `server_time` as the next cursor
- **Pros**: Simpler mental model ("give me the newest changes first").
- **Cons**: This was an earlier draft's actual design, and it has a real data-loss bug: if a response is capped at 200 rows (newest-first), persisting `server_time` as the next `since` advances the window forward *past* the older, still-undrained rows in that same change-set — they are never returned again.
- **Why not**: Directly falsified by tracing the capped-response case — ASC + last-row-cursor is the only direction that cannot lose data in a single-drain-pass sense.

### Alternative 3: Client computes `since` from its own device clock
- **Pros**: No dependency on a prior server response to bootstrap the first call.
- **Cons**: A fast or slow device clock could cause resolutions to be silently and permanently skipped (if the device clock is ahead of the server) or repeatedly re-fetched (if behind) — a classic clock-skew bug class.
- **Why not**: The server already returns `server_time` in every response specifically so the client never needs its own clock for this purpose; the first-call case (no server response yet) is solved by omitting `since` entirely rather than inventing a client timestamp.

## Consequences

### Positive
- No possible data-loss direction in the drain loop — ASC + last-row-cursor + explicit `has_more` handling was specifically checked against the capped-response case that broke the earlier `DESC` design.
- A run transitioning *into* `flagged` (not just *out of* it) is always surfaced, since the filter column (`updated_at`) is touched on every status-relevant mutation, not just terminal ones.
- Client never needs a locally-generated timestamp for this mechanism at any point — immune to device clock skew by construction.
- The call is entirely skipped when the client has nothing to watch (no locally-`flagged` runs) — avoids making this the highest-QPS endpoint in the system for users who never get flagged.

### Negative
- The design required its own local schema (server-mirror columns + a `SyncMeta` cursor entity, T0.6), its own server column with a DB-level trigger (`Run.updated_at`, T2.2), its own endpoint (T2.14c), its own client loop (T2.14d), and its own display logic (T2.14b) — five separate pieces that had to be designed as one unit; building any one in isolation (as the first four audit rounds found) leaves a gap.
- The ≥200-rows-sharing-one-`updated_at` termination case is a subtle edge case that must be explicitly tested, not just asserted in prose (database-api-spec.md §2.2b DoD) — an easy case to get wrong (infinite drain loop) if implemented casually.

### Risks
- Correctness here depends on `Run.updated_at` genuinely being touched by every relevant mutation via a DB-level trigger, not application code — if a future write path bypasses the trigger (e.g. a direct SQL migration or an admin script), reconciliation would silently miss that change. Mitigation: the trigger is DB-level specifically so no application code path can forget it.
