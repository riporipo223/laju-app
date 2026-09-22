# Laju — Documentation Index & Live Status

> **New Claude Code session (different device/account, no conversation history)? Read
> [HANDOFF.md](./HANDOFF.md) first, completely, before this file or anything else.** It is the
> self-contained orientation doc — reading order, workflow rules, current status, the recurring
> Apple Developer Program blocker, final decisions, and a security checklist for this public repo.

**Last updated: 2026-09-17.**

Two questions, answered in one place, so neither track has to ask the other what to do next:

- **§1 — Claude Code**: which task is next, and what unblocks it.
- **§2 — Design (manual)**: which screen to work on now, without waiting on code.

These two tracks are deliberately independent right now. Everything in §2 can be done while §1 proceeds, and vice versa.

> **Keep this current.** When a task closes or a screen is finished, update §1/§2 here in the same change. A stale status file is worse than none — this project has already been bitten once by a checklist that drifted out of sync with reality (`tasks/README.md`, corrected 2026-09-17).

---

## 1. Claude Code — what to build next

**Phase: Fase 1 (Core Loop Offline) — code complete, gate open.**

All Fase-1 code is written. Nothing is waiting on more implementation. What remains is device testing (§2's track) plus one open defect.

### Next, in order

| # | What | Why now | Blocked by |
|---|---|---|---|
| 1 | **Decide on CQ-2** — `RoutePointBuffer.flush` can silently destroy a recorded route | Open **Blocker** in [code-quality-audit.md](./04-quality-security/code-quality-audit.md). It defeats T1.14's crash-recovery guarantee. The audit reported it and deliberately changed no code — it needs a go-ahead | **Your decision.** Say the word and it gets fixed |
| 2 | **Fase 2's remaining work is not build work** | Every Fase-2 build task is now done or PARTIAL. What is left — T2.3/T2.4 (Sign in with Apple), T2.22's real-device half, T2.21's four open gate items, and the Apple-token revocation added to pre-launch §4 — all need the Apple Developer Program and a real signed-in device. Decision for you: enrol, or accept some items as limitations | Apple Developer Program |
| 3 | **T1.17 sign-off** — close the Fase 1 gate | Needs the dogfood runs in §2 | Device testing (§2) |

**T2.0a, T2.1, T2.2, T2.5, and T2.6 are closed. T2.3 and T2.4 are PARTIAL**, both on the same blocker: Sign in with Apple needs a paid Apple Developer Program membership, which the currently signed-in Apple ID's free Personal Team doesn't have — confirmed live via `xcodebuild`: *"Personal development teams... do not support the Sign In with Apple capability."* Everything backend-testable in both was verified live against real Supabase Auth JWTs (not mocks); only "call this from the app after a completed sign-in" is on hold. User is enrolling separately.

**Deploy flow changed 2026-09-19:** every Git deployment had been failing since the repo went monorepo — the Vercel project's Root Directory was `.` (repo root) but Next.js lives in `backend/`, so Git builds died with "Couldn't find any pages or app directory" while manual `vercel --prod` from `backend/` worked (which hid it: production always came from manual deploys, never from a push). Fixed: project Root Directory = `backend`, default function region = `sin1`, and `backend/vercel.json` gained an `ignoreCommand` so pushes that don't touch `backend/` skip the build. **Pushing to `main` now deploys production automatically** (first success: `baa0a31`); manual `vercel --prod` from `backend/` is no longer the path (expected to break with Root Directory set — not tested). **Not yet gated on CI** — a failing-test commit would still go live; a proper gate needs Vercel Pro's Deployment Checks, listed for pre-launch. Live infra as of 2026-09-18: Supabase project `laju` (ap-southeast-1), full 6-table schema migrated and functionally verified (trigger behavior, `GLOBAL` sentinel proven with real inserts), plus an 8th column (`run.resolved_via`, T2.11) and a unique constraint (`run_user_id_started_at_key` on `run(user_id, started_at)`, T2.12d — genuinely proved to reject a concurrent duplicate insert with a real Postgres 23505 error, not just asserted) and one seeded `Season` row (T2.17, `status=active`). Backend deployed at `https://backend-eight-gules-56.vercel.app` with 6 routes live — `/api/health`, `/api/auth/me`, `/api/profile/complete`, `/api/runs` (`POST` resolves real `validated`/`flagged`/`rejected` status via T2.12a, writes real `PointTransaction` ledger rows + updates `User.total_points`/`current_level` via T2.12c, and is now idempotent under retry/race via T2.12d — but see **PERF-1** above, its p95 fails budget; `GET ?since=` added T2.14c — status reconciliation for `flagged` runs resolved after sync, `updated_at`-filtered with `has_more` pagination, real `EXPLAIN ANALYZE` against 5000 seeded rows shows a 0.135ms Index Scan on `run_user_id_updated_at_idx`, well inside the 300ms NFR), `/api/seasons/active` (T2.17), `/api/users/me/progress` (T2.15 — server-authoritative points/level/trust_score, `total_points` verified live against an independently re-summed real `PointTransaction` ledger, not just the cached aggregate column), `/api/cron/resolve-flagged-runs` (T2.12f, secret-gated, registered in `vercel.json` as a real Vercel Cron job — daily, see **OPS-1** above) — plus `lib/point-calculation.ts` (T2.6), `lib/trust-score.ts` (T2.11), `lib/anti-cheat/status-resolution.ts` (T2.12a), `lib/point-transaction.ts` and `lib/levels.ts` (T2.12c, `pointsToNextLevel` added T2.15), `lib/anti-cheat/resolve-flagged-runs.ts` (T2.12b) plus a manual-override CLI (`backend/scripts/resolve-flagged-run.ts`) and its runbook (`04-quality-security/anti-cheat-resolution-runbook.md`). 145 backend tests passing (131 unit + 14 integration — the integration suite runs for real against the live Supabase project, both locally and in CI). T2.13's anti-cheat verification gate is **signed off** — T2.21's leaderboard-launch gate can treat it as passed. iOS side: T2.14 added `ios/Laju/Services/Networking/` (`APIClient`, `APIConfig`, `RunSubmissionDTOs`) and `ios/Laju/Services/Sync/` (`SyncService`, `NWPathMonitorAdapter`) — the app's first live connection to the backend, pushing offline-recorded runs to `POST /api/runs` and writing server fields back to Core Data. 97/97 iOS tests passing (89 previous + 8 new); app confirmed to boot cleanly in the Simulator with the real connectivity monitor wired in. **Both `ci-backend.yml` and `ci-ios.yml` are genuinely green for the first time in this repo's history as of 2026-09-18** — every prior run of either had failed since they were first added. `ci-ios.yml` needed 3 fixes along the way, none related to T2.14's own logic: real SwiftLint violations in the new test file (never run locally before pushing), a genuine `swiftformat`/`swiftlint` rule conflict over multiline-`if` brace placement (fixed by disabling `wrapMultilineStatementBraces`), and a CI-only Swift 6 concurrency error in unrelated pre-existing `RunHistoryView.swift` code caused by an Xcode-version difference between this machine and the GitHub Actions runner (fixed with `@preconcurrency import MapKit`). Final CI iOS run: [35331631809](https://github.com/riporipo223/laju-app/actions/runs/35331631809), `conclusion: success`, log confirms "Executed 97 tests, with 0 failures". All backend work through T2.13, plus T2.14 and earlier iOS Sign in with Apple/tab-shell/auto-pause work, committed and pushed to `main` (26+ commits, one per task). T2.0a additionally has one physical-device check open (an iOS 26.3 rendering artifact not reproducible against the iOS 16 deployment target from this machine), tracked in `deferred-manual-tests.md`; T2.14's real airplane-mode transition test is tracked there too.

None of Fase 2's remaining backend work (T2.6b onward) needs iOS or Fase 1 to be closed — it has been proceeding independently.

Full sequence: [03-development/tasks/README.md](./03-development/tasks/README.md). Testing layers and phase-exit rules: same file, "Testing Strategy" section.

### Open findings that are not tasks

Tracked separately; they do not block the sequence above.

| Finding | Severity | Blocks |
|---|---|---|
| [CQ-2](./04-quality-security/code-quality-audit.md) — route data loss | **Blocker** | Item 1 above |
| [SEC-1](./04-quality-security/security-review.md) — no GPS retention policy | **Blocker** | App Store submission (via Privacy Policy) |
| **No successor season exists** (2026-09-21) — `Season 1 — 2026` ends 2026-11-30; without a next season the hourly job reports `overrun` and Season 1 just stays active (nothing breaks, but it never rolls) | Note | Before 2026-11-30: `npx tsx --env-file=.env.local scripts/season.ts create "Season 2 — 2026" 2026-12-01T00:00:00Z 2027-02-28T23:59:59Z` from `backend/` |
| ~~**Region is free text** (2026-09-21) — the new onboarding profile step takes kecamatan / kabupaten-kota / provinsi as plain text, no catalog exists~~ **MOOT 2026-09-22: region removed entirely** (D1 reversed, Local Leaderboard cancelled) | ~~Note~~ Closed | ~~Local Leaderboard (v1.1): data must be normalized first; T3.1's cascading picker replaces the fields~~ No normalization needed — the fields and the never-built picker are both gone (Tasks B/C) |
| [SEC-9](./04-quality-security/security-review.md) — no API rate limiting | **RESOLVED 2026-09-21** by **T2.20a** (`6bea1a8`, verified live); SEC-10 (payload cap) closed with it | — |
| **PERF-1** — **PARTIALLY resolved 2026-09-19 (an earlier version of this line said fully resolved — that overclaimed).** Pinning Vercel to sin1 fixed the per-request cost: sequential `POST /api/runs` p95 = 463 ms (20 calls). But T2.12e's named load — 100 concurrent submissions — was re-run the same day (Fase 2 audit): all 100 returned 201 and all 100 rows persisted, yet **p95 = 3,827 ms (median 3,612, max 3,959) — still over the 1.5 s budget**, down from 7,801 ms. Median ≈ p99 means the requests queue behind one shared bottleneck (~25 submissions/s, ≈9 DB calls each), most plausibly Supabase Free-tier compute / PostgREST pool. **Decision 2026-09-19: accepted limitation, pending re-test after the Supabase Pro upgrade — not being optimized now** (see T2.12e). Not a concern at ~1 run/user/day, but the budget as written is not met. *(Original note: likely mostly a region mismatch — Vercel functions ran in iad1, Supabase is in ap-southeast-1; pinned to sin1 during T2.19 and `GET /api/leaderboard` fell from 2–3 s to p95 204 ms. NOT re-measured for `POST /api/runs` — re-run the T2.12e load test before treating this as closed.)* `POST /api/runs` p95 = 7801ms vs. tech-spec.md §4's 1.5s budget (measured 2026-09-18, T2.12e). Even an isolated single request is 4757ms — the bottleneck is ~9 sequential Supabase round-trips per request, not concurrency contention. No task currently owns fixing this; T2.12e's own scope explicitly excludes it ("a failing budget routes back to T2.12a/T2.12c for optimization") — full measurement in [phase-2-backend-sync-global-leaderboard.md](./03-development/tasks/phase-2-backend-sync-global-leaderboard.md)'s T2.12e section | T2.13/T2.21's release gate (p95 NFR must hold before public leaderboard ships) |
| **OPS-1** — `resolve-flagged-runs` Cron job runs daily (`0 0 * * *`), not the ≤12h T2.12f originally scoped, because Vercel's Hobby plan hard-rejects any cron expression running more than once per day (confirmed live 2026-09-18 via a real rejected deploy attempt with a 6h schedule). User chose the daily schedule over a Pro upgrade ($20/mo). Worst-case drift past the 48h `REVIEW_WINDOW_LOW` deadline is therefore up to 24h, not ≤12h | Low — LOW-confidence flags are the low-severity tier by design; only affects how long a likely-legitimate user's points stay off the leaderboard, not correctness. Revisit if/when the project upgrades to Vercel Pro |

---

## 2. Design (manual) — what to work on next

**You can start immediately. None of this waits on code.**

**All eight Fase-1 screens are already built and restyled** onto the black+lime system. There is no restyle backlog. The work is the screens that do not exist yet, plus states nobody has designed.

### Right now: Global Leaderboard (screen 11)

The highest-value thing you can design today. It is the **one genuinely new pattern in the product** — a dense repeating row with rank, name, points, and a pinned "your rank" row that stays visible while scrolling. Nothing existing gives you that for free, and T2.20 is far enough out that the design will not be rushed by implementation.

- Element checklist and states: [06-design/wireframe-spec.md](./06-design/wireframe-spec.md) §5
- Tokens (color, type, components): [06-design/design-notes.md](./06-design/design-notes.md)
- Motion and interaction already decided: [06-design/prototyping-reference.md](./06-design/prototyping-reference.md)

One caution worth reading before you start: ranks 1-3 invite a podium treatment, but the pinned own-rank row is what matters to the ~99% of users who will never be in the top 3. Do not let the podium outweigh it.

### Then, in priority order

| # | What | Where the spec is | Note |
|---|---|---|---|
| 2 | ~~**Region picker** (10)~~ **DROPPED 2026-09-22** | wireframe-spec §8 | ~~Three-level cascade over thousands of kecamatan. Solve on paper before T2.4/T3.1 codes it. Region stays **mandatory** in v1 (D1 final, 2026-09-21); its "why we ask" copy must be honest about the reason — wireframe-spec §8 item 4~~ **No longer design debt: region is removed entirely (D1 reversed, Local Leaderboard cancelled). The picker will never be built, and the "why we ask" copy problem disappears with the question itself.** |
| 3 | **Undesigned states on existing screens** | wireframe-spec §2, §1 | Cheap, and the thing that actually ships broken if skipped — see below |
| 4 | **Account Deletion** (14) | wireframe-spec §9 | Two screens, App Store blocker. Copy is a legal surface — coordinate with the Privacy Policy |
| 5 | **Season Info** (13) | wireframe-spec §7 | Last — reuses the leaderboard row from item 1 |

The states in item 3, specifically: Run Summary flagged / "sedang diverifikasi" (6d — the `warning` amber token was reserved for exactly this and has never been used), Run Summary after points change *downward* on a later resolution (6e), auto-paused as visually distinct from manual pause (5b, AC 4.11.2), and the empty states (6c, 7a). *(12a, the insufficient-data state, is deferred with the Local Leaderboard — 2026-09-21.)*

Full inventory with status and the visual dependency graph: [06-design/screen-inventory.md](./06-design/screen-inventory.md).

### Also yours: Fase-1 device testing

The remaining Fase-1 work is physical-device testing, which only you can run. Three outstanding items, all executable in **one batch of dogfood sessions**:

1. T1.8 — battery draw with the map on screen (screen unlocked, ~15-20 min moving)
2. T1.13 — audio cue with the screen locked (≥2km, two km boundaries)
3. T1.17 — ≥5 runs across ≥3 distinct days

Sequence them inside the same runs: start screen-on with the map visible, then lock the screen and keep going. Scenarios and pass conditions: [04-quality-security/deferred-manual-tests.md](./04-quality-security/deferred-manual-tests.md).

---

## 3. Open decisions — waiting on you

Not blocking either track today, but each will block something soon.

| # | Decision | Blocks | Detail |
|---|---|---|---|
| 1 | **Fix CQ-2?** | The Blocker in §1 item 1 | [code-quality-audit.md](./04-quality-security/code-quality-audit.md) |
| 2 | **GPS retention policy** — how long are routes kept, on device and on server? | Privacy Policy, which blocks App Store submission | [security-review.md](./04-quality-security/security-review.md) SEC-1 |
| 3 | **Low-trust leaderboard threshold** — below what `trust_multiplier` is a user hidden from the public leaderboard? | T2.19's third DoD item | The `trust_multiplier` formula itself is now defined (tech-spec §2.4), including its `0.3` floor. The separate threshold for *hiding* a user is still undefined. Moved out of T2.11 on 2026-09-17 because verifying it needs T2.19, which transitively depends on T2.11 — the DoD item could never be checked in sequence | **RESOLVED 2026-09-19:** cutoff `trust_score < 0.5` hidden (user decision, T2.19); one constant `v_min_trust` in the leaderboard precompute migration.
| 4 | **Observability for the two Vercel Cron jobs** | Nothing yet; becomes real in Fase 2 | No document covers monitoring or alerting for precompute / `resolve-flagged-runs`. If either stops, failure is silent |
| 5 | **`user-flow.md` reconciliation** — Circle, Social Feed, Freemium/Premium tiering | Nothing today; it is correctly parked | That document is still labelled "draft standalone, belum diintegrasikan". Screens there are excluded from the design inventory on purpose |
| 6 | **Onboarding step order** — code runs sign-in *before* location permission; `user-flow.md` §2.1 still says the reverse | Nothing today, but the two documents disagree | Confirmed visually on simulator 2026-09-17: the running order is Welcome → Core Loop → Sign in → Permission. The 2026-09-14 code comment says user-flow.md should be updated if this order is kept. Confirm, then sync the doc |
| 7 | **T2.9's teleport threshold (150km/h) is a starting value, not spec-given** | Nothing today; flagged for the same real-data calibration pass as the pace-bracket table and `MIN_DISTANCE_KM_FOR_POINTS` | tech-spec.md §2.4's Distance/duration sanity row has no explicit number, unlike pace cap (3:00/km) and speed jump (25km/h) — `backend/lib/anti-cheat/distance-duration-sanity.ts` documents the value and its rationale inline, following the project's own established convention |

### Closed 2026-09-21

| Was | Resolution |
|---|---|
| **D1 — is region still mandatory in v1?** | ~~**Closed: yes, region stays mandatory (final).** Cost is low (one onboarding/profile field); benefit is clear — it prepares data for the deferred Local Leaderboard and avoids re-onboarding every existing user later. No code or AC change: T2.5's `409` guard, AC 4.1.2 and T3.1 stand as built.~~ **REOPENED AND REVERSED 2026-09-22 (PM sign-off): region is removed entirely** — not mandatory, not optional, not collected at all. D1's whole benefit argument ("prepares data for the deferred Local Leaderboard") collapsed when Local Leaderboard was cancelled permanently rather than deferred. Replacement: Global leaderboard visibility gated on granted location permission (§4.5 AC5). T2.5's `409` guard, AC 4.1.2 and T3.1 are all being reworked/removed (Tasks B and C). [product-spec.md](./01-product/product-spec.md) §4.1 AC2 |
| **W4 — what does "tier" mean in the Premium leaderboard AC?** | **Closed: Season League** (division), derived from points earned *during the current season*, resets each season — not Level, not Rank. Defined in [tech-spec.md](./02-architecture/tech-spec.md) §2.5; new task **T3.7a** in Fase 3 computes it. [product-spec.md](./01-product/product-spec.md) §4.5 AC4 |

### Closed 2026-09-17

| Was | Resolution |
|---|---|
| **Navigation shell undecided** — Leaderboard/Season unreachable, no task owned it | **Closed.** `TabView` built with two tabs (Track, You), `RootTabView` is the app root. New task **T2.0a** owns it, placed first in Fase 2 so T2.20/T3.5 (deferred to Fase 4, 2026-09-21)/T3.9 have an entry point. Structure takes a third tab as one enum case plus one `tabItem` block |
| **`trust_multiplier` undefined** — T2.11 not executable | **Closed.** Formula defined in [tech-spec.md](./02-architecture/tech-spec.md) §2.4: base 1.0, −0.10 per HIGH flag, −0.05 per non-auto-approved LOW flag, +0.02 per clean run, floor 0.3, ceiling 1.0, rolling 30-day window. T2.11 rewritten with 9 checkable DoD items |
| **T2.14 family listed out of dependency order** | **Closed.** Reordered to T2.14 → T2.14c → T2.15 → T2.16 → T2.14d → T2.14b, in both the phase file and the checklist. The `Depends on` fields were already correct; only the listing order was wrong |
| **T3.9 orphaned** — Fase 3 could close with the Season screen unbuilt | **Closed.** Added to T3.10's `Depends on`, plus a DoD item verifying the countdown and past-season rank |
| **Gate rule asserted but unenforced** | **Closed.** The three phase-wide gates (T1.17, T2.21, T3.10) now carry a DoD item requiring every `deferred-manual-tests.md` row for their phase to be Pass or a documented accepted limitation. T2.13 is deliberately excluded — it is a narrow anti-cheat gate, and sweeping there would let an unrelated row block anti-cheat sign-off |

---

## 4. Folder map

| Folder | Contains | Start here |
|---|---|---|
| **01-product** | Why the product exists and what it must do | [product-spec.md](./01-product/product-spec.md) — §4 is the acceptance-criteria source of truth |
| **02-architecture** | How the system is built, and why | [architecture.md](./02-architecture/architecture.md), then [adr/](./02-architecture/adr/README.md) for the 13 recorded decisions |
| **03-development** | What to build, in what order | [tasks/README.md](./03-development/tasks/README.md) |
| **04-quality-security** | What is broken, risky, or untested | [security-review.md](./04-quality-security/security-review.md), [code-quality-audit.md](./04-quality-security/code-quality-audit.md) |
| **05-reports** | Point-in-time records; historical, not live | [audit-report.md](./05-reports/audit-report.md) |
| **06-design** | Everything needed to design a screen | [screen-inventory.md](./06-design/screen-inventory.md) |

### Reading order for someone new

1. [lean-canvas.md](./01-product/lean-canvas.md) — the business case, 5 minutes
2. [product-spec.md](./01-product/product-spec.md) §3-§4 — scope and acceptance criteria
3. [architecture.md](./02-architecture/architecture.md) — the system in one document
4. [tasks/README.md](./03-development/tasks/README.md) — the work

Two documents are **not** current-state and should be read as history: [audit-report.md](./05-reports/audit-report.md) (Round 7 snapshot) and [user-flow.md](./01-product/user-flow.md) (unreconciled draft — see §3 item 5).

---

## 5. Status at a glance

| Phase | State | Gate |
|---|---|---|
| **Fase 0** — Setup | **Closed.** Background survival ~59min, 3%/hour battery, force-kill integrity all verified on device | T0.9 passed |
| **Fase 1** — Core Loop Offline | **Code complete.** 14 of 17 tasks fully closed; T1.8 and T1.13 are PARTIAL (one deferred device test each); T1.17 is the open gate | T1.17 open — needs dogfood runs |
| **Fase 2** — Backend + Sync + Global Leaderboard | 26/33 closed (corrected 2026-09-21 from an earlier miscount of 27/32; T2.20a rate limiting now done: T2.20 — global leaderboard screen, T2.19 — GET /api/leaderboard, T2.18 — global leaderboard precompute via pg_cron, T2.14b — anomaly reason/status copy, T2.14d — client reconciliation loop, T2.16 — server-backed profile screen, T2.0a, T2.1, T2.2, T2.5, T2.6, T2.7, T2.8, T2.9, T2.10 — all 4 anti-cheat checks done, T2.11 — trust score, T2.12a — anti-cheat pipeline wired, T2.17 — seasons endpoint+seed, T2.12c — ledger write + aggregate, T2.12d — duplicate idempotency, T2.12e — load test done, but its measurement **failed** the p95 budget, tracked as **PERF-1** above, T2.12b — flagged-run resolution lifecycle, T2.12f — cron registered, daily not ≤12h, tracked as **OPS-1** above, **T2.13 — anti-cheat verification gate signed off**, T2.14 — mobile sync queue, first client-side Fase 2 code, T2.14c — GET /api/runs status reconciliation endpoint, deployed and live-verified, T2.15 — GET /api/users/me/progress endpoint, deployed and live-verified), 4 PARTIAL (T2.3, T2.4 — Apple Developer Program; T2.6b — genuine GPS routes, device disconnected; T2.22 — server side verified, real-device half open). no build task left in Fase 2 — remainder needs the Apple Developer Program / a signed-in device; T2.21 gate NOT passed (4/8 items met since T2.20a; 4 open, all needing the Apple Developer Program or a real device) | T2.13 + T2.21 |
| **Real chain check 2026-09-21** | Sync, reconciliation, Profile and Ranks verified against the real server with a real Supabase session in the Simulator (no Sign in with Apple). It found and fixed a defect that made every real run fail to sync (fractional duration → `500`), see [phase-2 file](./03-development/tasks/phase-2-backend-sync-global-leaderboard.md). Repeated the same day with a **real Google sign-in** (Google added as a second provider, reversing "Apple only" — see product-spec §4.1 AC1): the sign-in itself, session persistence across a force-quit, sync, reconciliation, Profile and Ranks all verified. Only Sign in with **Apple** remains unverified. The two findings that run exposed were **fixed the same day**: the server now awards the streak bonus (estimate 2.58 → awarded 3, was 1) and the app now has a profile step that creates the `user` row itself (no seeding needed). | — |
| **Fase 3** — Season | **DONE 2026-09-22.** All 7 tasks complete: T3.1, T3.6, T3.7, T3.7a, T3.8, T3.9, T3.10 (T3.7a = Season League, added 2026-09-21). T3.10's composite close→open-cycle test (3 seeded users) signed off the phase — see [phase-3-season.md](./03-development/tasks/phase-3-season.md). **Scope change 2026-09-21:** Local Leaderboard cut from MVP v1 — T3.2–T3.5 moved intact to Fase 4 / v1.1 (deferred, not cancelled; needs high user density); v1 leaderboard is Global only. **Superseded 2026-09-22: T3.2–T3.5 CANCELLED PERMANENTLY** (scope too broad), and T3.1 is **superseded/needs rework** — region removed entirely (D1 reversed), so this phase is no longer fully "DONE" in the sense its sign-off implies. Renamed from "Local Leaderboard + Season"; file is now `phase-3-season.md` | — |
| **Fase 4** — Backlog | Not scheduled. Do not build | — |
