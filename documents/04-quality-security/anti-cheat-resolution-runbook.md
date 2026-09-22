# Anti-cheat resolution runbook (manual override)

Created 2026-09-18 (T2.12b). Direct DB action, no admin UI — per
product-spec.md §5, an admin review UI is explicitly out of v1 scope.
This is the documented procedure an operator follows to manually
resolve a `flagged` run early, instead of waiting for LOW-confidence's
`REVIEW_WINDOW_LOW` auto-approve (HIGH-confidence never auto-resolves
at all — it stays `flagged` until this runbook is used).

## When to use this

- A HIGH-confidence `flagged` run (`excluded_pct` 25%–<50%) needs a
  human decision — it will never resolve on its own.
- A LOW-confidence `flagged` run needs an *earlier* decision than the
  default 48h auto-approve window (e.g. a user reports it, or an
  operator spot-checks it and wants to clear/reject it sooner).

## Finding candidate runs

```sql
select id, user_id, flag_confidence, excluded_pct, anomaly_flags,
       final_points_awarded, created_at
from run
where status = 'flagged'
order by
  case flag_confidence when 'high' then 0 else 1 end, -- HIGH first, it never expires on its own
  created_at asc;
```

`anomaly_flags` names which anti-cheat check(s) triggered
(tech-spec.md §2.4) — use it, and a look at the run's `gps_route` if
needed, to judge whether the flag looks like genuine cheating or GPS
noise/urban-canyon drift.

## Resolving a run

Run this from `backend/`, with a real `SUPABASE_SERVICE_ROLE_KEY` in
`.env.local` (never the anon key — this needs to bypass RLS the same
way every other server-side write in this codebase does):

```bash
npx tsx --env-file=.env.local scripts/resolve-flagged-run.ts <run_id> approved
# or
npx tsx --env-file=.env.local scripts/resolve-flagged-run.ts <run_id> rejected
```

This calls `resolveFlaggedRun` (`backend/lib/anti-cheat/resolve-flagged-runs.ts`)
directly — the same function the LOW-confidence auto-resolve job
(T2.12f) uses, just with `resolved_via='manual'` instead of `'auto'`.
Using this script instead of hand-written SQL is deliberate: the
reject path's compensating `PointTransaction` amount and the
`trust_multiplier` recomputation both depend on the run's and user's
current DB state in ways that are easy to get wrong by hand and are
already correctly implemented (and tested) in that function.

**What each outcome does** (tech-spec.md §2.4.1):

| Outcome | Effect |
|---|---|
| `approved` | `run.status → approved`, `resolved_at`/`resolved_via='manual'` set, `flag_confidence` retained. The partial `PointTransaction` already written when the run was first flagged (T2.12c) becomes leaderboard-eligible — no new ledger row. |
| `rejected` | `run.status → rejected`, `final_points_awarded → 0`. A compensating negative `PointTransaction` (`type='adjustment'`) nets the original partial amount to zero — the original transaction is never edited or deleted (append-only ledger, tech-spec.md §4). `User.total_points`/`current_level` recomputed from the ledger. |

Either way, the user's `trust_score` is recomputed immediately
afterward — this is what makes a LOW flag's manual-approve *not*
exempt it from decay (only `resolved_via='auto'` is exempt, T2.11
§2.4), while a HIGH or LOW flag resolved to `rejected` keeps
decaying it.

## Safety notes

- The script refuses to act on a run that isn't currently `flagged`
  (`RunNotFlaggedError`) — it cannot be used to re-resolve an
  already-resolved run or to reject a `validated` run outright (that
  path is `POST /api/runs`'s own immediate-reject, T2.12a).
- There is no undo. Re-running the script on an already-resolved run
  fails fast rather than silently double-writing a second compensating
  transaction.
