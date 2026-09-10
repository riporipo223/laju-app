# Laju App — Pre-Execution Audit Report (Round 6 — iOS/Swift Pivot)

Scope: all files in `Laju/documents/` after the platform pivot (React
Native/cross-platform → native iOS-exclusive Swift/SwiftUI, Android
postponed indefinitely). Two independent audits run in parallel
(`ecc:architect` — system design/consistency, `ecc:planner` —
task-graph/dependency/traceability), findings merged below. All Blockers
tagged Fase 0/1, plus the Fase 2 Blockers directly inside the
status-reconciliation feature (already hardened across 4 prior audit
rounds), were fixed in this pass. Remaining Fase 2/3 Notes are logged, not
fixed — per this round's gating rule, they do not block Fase 0/1 execution.

**Verdict: Fase 0/1 — CLEAN after fixes below. Fase 2/3 — 1 open Note
each, non-blocking. Do NOT auto-start T0.9 — physical environment
(full Xcode.app + connected device) must be reconfirmed by the user first
(see final summary).**

---

## Part 1 — Grep sweep (leftover pre-pivot references)

Independently re-verified by both agents beyond the editor's own sweep:
**clean.** Every surviving `react-native`/`SQLite`/`TanStack`/`Zustand`/
`apps/mobile`/`apps/backend`/`packages/shared-types` string in the corpus
is deliberate historical framing (e.g. "this pivot replaces X", "before
the pivot Y worked like this") or an explicitly-labeled Future Development
Android mention. No task treats the removed `T0.5` (Android dev-client
build) as live.

---

## Part 2 — Blockers found, and fixes applied this pass

| # | Phase | Finding | Fix applied | Files touched |
|---|---|---|---|---|
| B6-1 | Fase 1 | `T1.1`'s `Depends on: T0.1` stale for the Swift rewrite — task now creates real Swift source + XCTest content in `ios/LajuTests`, which doesn't exist until `T0.2` | `Depends on: T0.1, T0.2`; `T0.2` scope/DoD extended to create the `ios/LajuTests` XCTest target and configure SPM | tasks/phase-1-core-loop-offline.md, tasks/phase-0-setup.md |
| B6-2 | Cross-cutting (Fase 0→1→2) | `shared/point-formula.fixtures.json` created as an empty `[]` placeholder (T0.1) with no task ever required to populate it — the entire cross-language parity guarantee (tech-spec §2.2b) was vacuously satisfiable | `T1.1` now explicitly owns authoring the fixture content, with a DoD item requiring coverage of every pace bracket boundary + streak 0/1/7/8 + zero-distance, and a row-count assertion so an empty fixture fails the test; `T2.6`'s DoD gained the matching non-empty assertion | tasks/phase-1-core-loop-offline.md, tasks/phase-2-backend-sync-global-leaderboard.md |
| B6-3 | Fase 0 | `T0.8` only persisted the `Run` object on Stop — `T0.9`'s force-kill DoD ("data recorded up to the last point before kill is not lost") is unachievable if a mid-run kill leaves no row at all | `T0.8` rewritten: `Run` object created and saved at Start, GPS points appended with incremental context saves while active, finalized on Stop; `T0.9`'s DoD reworded to reference "last incremental save" | tasks/phase-0-setup.md |
| B6-4 | Cross-cutting (Fase 0→2) | No task owned the CI pipeline, despite `repo-coding-rules.md` §3 ("PRs cannot merge with lint failing") and `T2.13`'s DoD ("test suite is part of CI") both assuming one exists | New **T0.10** — path-filtered `ios/`/`backend/` lint+format+test CI, depends on T0.3 (iOS half) and T2.1 (backend half) | tasks/phase-0-setup.md, tasks/README.md |
| B6-5 | Fase 1 | `T1.7` (Fase 1 DoD gate) didn't depend on `T1.2b`, the sole owner of AC 4.2.3 (pause/stop) — a graph leaf nothing gated on, same failure class the AC coverage matrix was built to catch | `T1.7` `Depends on` now includes `T1.2b` | tasks/phase-1-core-loop-offline.md |
| B6-6 | Cross-cutting (Fase 1+2) | `database-api-spec.md` claimed level-threshold parity is "kept in sync via the same fixture-parity approach as the point formula" — but the fixture schema has no level dimension, and neither `T1.3` nor `T2.15` had a DoD item verifying it | `T1.3` and `T2.15` DoD both gained "`levelThresholds` values match database-api-spec.md §1's table exactly, row for row — verified by test"; database-api-spec.md §1 prose corrected (small/static table → direct match-test, not a JSON fixture) | tasks/phase-1-core-loop-offline.md, tasks/phase-2-backend-sync-global-leaderboard.md, database-api-spec.md |
| B6-7 | Fase 2 (reconciliation feature) | `T2.16`'s scope (server-fetched `@Published` state) is incompatible with tech-spec §3 step 7 / architecture §2 step 10 / `T2.14d`'s claim that a **Core Data change notification** triggers the profile/progress refresh — saving a `Run` object never re-runs a `URLSession` call, so a background-resolved run's points/level would never actually update on screen | `T2.16` given an explicit `ProgressViewModel.refresh()` hook; `T2.14d` now calls it explicitly (separately from the Core Data save, which only re-renders the run's own row); tech-spec §3 step 7, architecture §2 step 10, and `T2.14d`'s DoD reworded to describe two distinct mechanisms instead of one | tasks/phase-2-backend-sync-global-leaderboard.md, tech-spec.md, architecture.md |
| B6-8 | Fase 2 (reconciliation feature) | `T2.14d`'s DoD said every call after the first "sends the previously-persisted `server_time`" — contradicting its own Scope (and database-api-spec/architecture), which correctly says the cursor is `server_time` only when `has_more: false`, else the last row's `updated_at`. An implementer following the DoD literally reintroduces the exact data-loss bug this endpoint was redesigned to fix (Round 4/5) | DoD reworded to describe the conditional cursor correctly | tasks/phase-2-backend-sync-global-leaderboard.md |
| B6-9 | Fase 2 (reconciliation feature) | database-api-spec.md §2.2b already specifies a drain-loop termination guard (break once a follow-up call returns no row newer than the cursor, for the ≥200-rows-sharing-one-`updated_at` edge case) — but `T2.14d`'s own Scope/DoD never mentioned it, so an implementer working from the task file alone could ship an infinite loop against a live endpoint (`resolve-flagged-runs` resolving many LOW runs in one invocation is exactly the trigger case) | Termination guard copied into `T2.14d`'s Scope, with a matching DoD item | tasks/phase-2-backend-sync-global-leaderboard.md |

---

## Part 3 — Notes logged, not fixed this pass (Fase 2/3-only or cosmetic — do not block Fase 0/1)

| # | Phase | Finding | Suggested fix (for a future round) |
|---|---|---|---|
| N6-1 | Cross-cutting | tech-spec.md/architecture.md use snake_case client field names (`sync_status`, `server_run_id`, ...) without database-api-spec.md's Core Data-mapping disclaimer; tech-spec §3 step 7 also still says "kolom" (column) once, which tech-spec §1 itself rules out for Core Data | Add the same one-paragraph disclaimer to tech-spec §3/architecture §2-§3; swap remaining "kolom" → "atribut" |
| N6-2 | Fase 2 | architecture.md §3 claims Core Data caches a "leaderboard snapshot for offline viewing" but no task creates that entity or populates it (T0.6 makes only `Run`/`SyncMeta`; T2.20 has no offline-cache DoD item) | Either drop the clause, or add a `LeaderboardSnapshot` entity + T2.20 DoD item in a future round |
| N6-3 | Fase 0/2 | `T0.7`/`T0.8` (GPS capture) and `T2.3` (Auth SDK in SwiftUI screens) don't name the `Services/Location`/`Services/Persistence`/`Services/Auth` seams architecture.md §3 mandates ("only Data/Sync talks to CLLocationManager/network") | Name the service-layer seam explicitly in each task's Scope in a future round |
| N6-4 | Fase 1/2 boundary | T1.3's offline level derivation still sums `estimatedPoints` even after a run has a server-authoritative `finalPointsAwarded` (post-T2.14) — an offline user can see a level computed from pre-validation estimates for an already-resolved run | Add a DoD item (T2.16 or T2.14) requiring the local derivation to prefer `finalPointsAwarded` when non-nil |
| N6-5 | Fase 1 | `levelThresholds` sharing a directory (`ios/Laju/PointFormula`) with the point formula means a level-title tuning PR trips repo-coding-rules §4's point-formula second-reviewer/fixture gate without actually touching the formula | Move level config to its own directory, or scope the PR-gate clause to point-formula files specifically |
| N6-6 | Fase 2 | `tasks/README.md`'s Fase 2 checklist lists some tasks before their own dependencies (T2.12c before T2.17, T2.14b before T2.14c/d, T2.14d before T2.16) — thematic grouping, not execution order, but unstated as such | Add a one-line note that checklist order is thematic; or reorder to topological order |
| N6-7 | Fase 2 | `T2.11`'s DoD includes an item only closeable once `T2.19` exists (8 tasks later), making T2.11 read as permanently incomplete | Move that DoD item to T2.19 (which already has an equivalent), leave T2.11 with a scope note only |
| N6-8 | Fase 3 | `T3.1`'s `Depends on: T2.4` doesn't include `T2.5`, though its DoD verifies T2.5's `409` behavior | `Depends on: T2.4, T2.5` |
| N6-9 | Cross-cutting | tech-spec.md §2.2b (cross-language point-formula parity) sits out of numeric order, appended after §2.3 instead of directly after §2.2 | Renumber/reorder in a future documentation pass — nine cross-references would need updating |

None of N6-1 through N6-9 affect Fase 0 or Fase 1 execution readiness.

---

## Part 4 — What was verified intact (unaffected by the pivot)

- Anti-cheat state machine (`validated|flagged|approved|rejected`),
  count-based `excluded_pct`, LOW/HIGH confidence split, `REVIEW_WINDOW_LOW`,
  and "only T2.12a owns status" — consistent across tech-spec §2.4/§2.4.1,
  database-api-spec §3, T2.7–T2.13.
- Region hierarchy (kecamatan → kabupaten_kota → provinsi) and
  `LEADERBOARD_SCOPE` `scope_id='GLOBAL'` sentinel, including Fase 2
  migration timing — consistent everywhere.
- `GET /api/runs?since=` server contract itself (ASC + last-row cursor,
  `server_time`, `has_more`, 200-row cap, `updated_at` DB trigger, 90-day
  cold-start default, cross-user scoping) — internally consistent; the
  bugs found this round (B6-7/8/9) were all on the **client task's**
  description of that contract, not the contract itself.
- AC Coverage Matrix: all 21 Must-have ACs map 1:1 to product-spec.md §4,
  every owning task ID still exists post-rewrite with a matching
  scope/title. The "5 Partial" count is unchanged by this pivot.
- Backend/server architecture (Next.js, Postgres/Supabase, Vercel Cron
  jobs, auth) — untouched by the pivot, as required.

---

## Part 5 — Repo structure decision (from this round)

**Monorepo, `ios/` + `backend/`**, not separate repos. Reasoning: the API
contract between client and server is the one thing that must still change
atomically across both sides even though the languages diverged; a single
repo keeps that PR-atomic, plus one docs folder, one issue tracker, one CI
config for a small/solo team. No root-level JS build orchestration
(Turborepo/pnpm workspaces) — `ios/` and `backend/` build independently,
CI path-filters between them (T0.10). Full reasoning in
[repo-coding-rules.md](./repo-coding-rules.md) §1.
