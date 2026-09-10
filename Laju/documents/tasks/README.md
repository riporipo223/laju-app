# Laju App — Task Backlog

Granular breakdown of [development-plan.md](../development-plan.md), one
file per phase. Use this checklist as the progress tracker; details, Scope,
Depends on, and Definition of Done for each task live in the linked file.

## Must-have AC Coverage Matrix

Added after 4 audit rounds found the same class of gap repeatedly (AC
4.2.3 and AC 4.3.2 both went uncovered for 3 rounds despite their parent
*features* being "covered") — the root cause was that this backlog had no
**spec → task** traceability, only **task → spec** (each task's
`Reference:` field), and that field's granularity was inconsistent (some
tasks cite a specific AC, others cite a whole section containing several
ACs, which reads as "covered" when only one of its ACs actually is).

**Rule going forward:** every Must-have AC in
[product-spec.md](../product-spec.md) §4 must have a row below with at
least one owning task and a real DoD item that verifies it — not just a
task that touches the feature. Adding or changing an AC in product-spec.md
§4 must update this table in the same change. A `Partial` status means an
owning task exists but no DoD item verifies the AC's specific claim
(usually a number or an explicit behavioral assertion) — these are
tracked, not silently treated as done.

| AC | Requirement (short) | Owning task(s) | Verified by DoD? |
|---|---|---|---|
| 4.1.1 | Sign-up in ≤3 steps | T2.3 | **Partial** — T2.3's DoD doesn't assert the step count |
| 4.1.2 | Region required before first run submits | T2.4, T2.5, T3.1 | Yes |
| 4.1.3 | Login persists across app restarts | T2.3 | Yes |
| 4.2.1 | ≥60 min background tracking, ≤5% distance drift | T0.8, T0.9 | **Partial** — T0.8 says "reasonable GPS tolerance", no task asserts the 5% figure numerically |
| 4.2.2 | Data survives OS force-kill | T0.9 | Yes |
| 4.2.3 | Start/pause/stop clearly from UI | T1.2b | Yes |
| 4.3.1 | Local point estimate in <2s | T1.2 | Yes |
| 4.3.2 | Final points + reason shown if they differ, incl. later resolution | T2.14, T2.14b, T2.14c, T2.14d | **Partial** — flagged/approved/rejected divergence fully covered; a `validated` run whose points differ due to `trust_multiplier` or sub-`FLAG_THRESHOLD_PCT` exclusion has no owning copy (`trust_multiplier` itself is undefined/unexposed — tech-spec §2.2/§2.4) |
| 4.3.3 | Implausible-pace runs don't get full points automatically | T2.7, T2.12a, T2.13 | Yes |
| 4.4.1 | Level from lifetime cumulative points, never resets | T1.3, T2.12c | Yes |
| 4.4.2 | Level-up notification/visual | T1.3 | **Partial** — only asserted for local/offline level-ups; T2.16 (server-backed screen) has no DoD item for a level-up triggered by a later server-side change (e.g. a `flagged` run resolving to `approved`) |
| 4.4.3 | Points-to-next-level visible on profile | T1.6, T2.16 | Yes |
| 4.5.1 | Top N + own rank shown | T2.20 | Yes |
| 4.5.2 | Leaderboard data ≤15 min stale | T2.18, T2.20 | Yes |
| 4.5.3 | Leaderboard scoped to active season | T2.18 | Yes |
| 4.6.1 | Filter by kecamatan/kabupaten-kota/provinsi | T3.4, T3.5 | Yes |
| 4.6.2 | "Belum cukup data" message for low-density regions | T3.3, T3.5 | Yes |
| 4.6.3 | Region from profile, not per-run GPS (anti leaderboard-shopping) | T3.2, T3.5 | **Partial** — stated in Scope prose ("Yang TIDAK dikerjakan"), no DoD item tests it |
| 4.7.1 | Rank resets on season transition; lifetime stats don't | T3.7 | Yes |
| 4.7.2 | Time remaining in active season visible | T3.9 | Yes |
| 4.7.3 | Final season rank retained, viewable after season ends | T3.8 | Yes |

**5 `Partial` rows remain** (4.1.1, 4.2.1, 4.3.2, 4.4.2, 4.6.3) — none
block the reconciliation feature (4.3.2's Partial is a narrower,
separate gap — `trust_multiplier` exposure — left after the
reconciliation redesign closed the flagged/approved/rejected half of
that AC). Tracked here, not fixed in this pass, so they don't repeat the
pattern of silently surviving future rounds unnoticed.

## Fase 0 — Setup
- [x] T0.1 — Init repo scaffolding (monorepo: ios/ + backend/) (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.2 — Init native Xcode project (Swift + SwiftUI, iOS 16 min) — all DoD items verified: builds/runs on iOS Simulator (iPhone 17, iOS 26.3), iOS 16.0 deployment target, XCTest target running (2 tests passing), SPM configured, Strict Concurrency/warnings-as-errors enabled (and caught 2 real bugs) (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.3 — Configure SwiftLint/SwiftFormat across the iOS app — 0 violations, both tools installed & config verified clean (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.4 — iOS build running on physical device — verified on iPhone 13 (iOS 18.6.2), team `NTHHTF27HU`, bundle id `com.designbyripo.laju` (moved off `com.laju.app` — globally collided with a different Apple Developer account); steps + blockers documented in `ios/README.md` (lihat [phase-0-setup.md](./phase-0-setup.md))
- ~~T0.5 — Android dev-client build~~ — removed, Android postponed with no timeline (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.6 — Set up local Core Data schema for runs (data/sync layer skeleton) — all DoD items verified via `PersistenceTests` (XCTest, passing) + real on-device data (13 Run rows inspected directly in the on-device SQLite store). Real bug found + fixed along the way: `NSPersistentContainer(name:)` re-parsing the model per-instance caused a Core Data entity-ambiguity error when 2 `PersistenceController`s existed in one process — fixed by caching the parsed model (see `PersistenceController.swift`) (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.7 — Integrate CLLocationManager (permissions, background config) — all 3 DoD items verified on device: permission-prompt flow, background delivery (~59min), and console logging (4 real GPS points captured live via `devicectl --console` over ~2min) (lihat [phase-0-setup.md](./phase-0-setup.md))
- [~] T0.8 — Basic start/stop run UI persisting raw GPS trail to Core Data — 2/3 DoD items verified on device (non-empty GPS trail, incremental saves proven mid-run against the SQLite store); distance/duration accuracy only loosely spot-checked against indoor GPS noise, not a calibrated known-route test (lihat [phase-0-setup.md](./phase-0-setup.md))
- [~] T0.9 — Verify background tracking survival + battery benchmark (phase DoD gate) — **partial — DEFERRED: battery drain retest.** 3/4 DoD items PASSED on physical device (iPhone 13, iOS 18.6.2): background survival (~59min continuous, screen locked + other apps used), GPS capture pipeline (Always permission → points/distance updating live), force-kill data integrity (verified directly against the on-device SQLite store — a real bug was found here, a count-only incremental-save threshold that never triggered for a low-activity session, and fixed with a time-based flush backstop, see RunViewModel.swift). Remaining: **battery drain <5%/hour not yet cleanly measured** — the one battery datapoint collected (62%→39%/55min) is contaminated by heavy foreground use (camera, video, hotspot) during that run, not attributable to background GPS overhead. Deferred, not skipped — needs a clean retest (phone unplugged, locked/idle, no other heavy app use, ≥30min) before this item can close. See phase-0-setup.md T0.9 for full DoD detail (lihat [phase-0-setup.md](./phase-0-setup.md))
- [~] T0.10 — CI: path-filtered lint/format/test pipeline (ios/ + backend/) — **partial**: workflow file written (`.github/workflows/ci.yml`); not yet exercised — no git remote/host connected yet (lihat [phase-0-setup.md](./phase-0-setup.md))

## Fase 1 — Core Loop Offline
- [ ] T1.1 — Implement calculatePoints in ios/Laju/PointFormula with XCTest (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [ ] T1.2 — Post-run summary screen wired to point-formula (offline estimate) (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [ ] T1.2b — Pause/resume run tracking (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [ ] T1.3 — Local level progression from cumulative points (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [ ] T1.4 — Local streak tracking feeding streak_bonus (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [ ] T1.5 — Local run history screen (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [ ] T1.6 — Local profile/progress screen (offline) (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [ ] T1.7 — Internal dogfood QA pass (phase DoD gate) (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))

## Fase 2 — Backend + Sync + Global Leaderboard
- [ ] T2.1 — Provision Supabase project + Next.js backend skeleton on Vercel (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.2 — Migrate core DB schema (User, Run, PointTransaction, Season, LeaderboardEntry, LeaderboardScope) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.3 — Supabase Auth integration (mobile sign up/in + backend JWT verification) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.4 — POST /api/profile/complete endpoint (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.5 — POST /api/runs endpoint — ingestion only (no calc/anti-cheat yet) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.6 — Server-side point calculation module (fixture-parity with client formula) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.6b — Build GPS test fixture corpus (spoofed vs. real) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.7 — Anti-cheat check: pace cap (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.8 — Anti-cheat check: GPS speed jump detection (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.9 — Anti-cheat check: distance/duration sanity (teleport detection) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.10 — Anti-cheat check: elevation anomaly signal (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.11 — Trust score model + trust_multiplier (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.12a — Wire anti-cheat pipeline + aggregate status resolution (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.12c — PointTransaction ledger write + User aggregate + season linkage (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.12d — Duplicate submission idempotency (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.12e — Load test / p95 latency verification (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.12b — Anti-cheat resolution & auto-approve/reject lifecycle (confidence-based) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.12f — Register resolve-flagged-runs as Vercel Cron job (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.13 — Anti-cheat verification pass (synthetic bad-data test suite) — gate task (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.14 — Mobile sync queue (offline → online push, retry, initial status apply) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.14b — Surface anomaly reason & resolution status to user (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.14c — GET /api/runs status reconciliation endpoint (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.14d — Client status reconciliation loop (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.15 — GET /api/users/me/progress endpoint (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.16 — Update mobile profile/progress screen to use server data (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.17 — GET /api/seasons/active endpoint + seed initial season (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.18 — LeaderboardEntry precompute job (global scope) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.19 — GET /api/leaderboard endpoint (global scope) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.20 — Global leaderboard screen on mobile (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.21 — Phase gate: confirm anti-cheat verified before enabling public global leaderboard (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))

## Fase 3 — Local Leaderboard Granular + Season System
- [ ] T3.1 — Mobile onboarding UX blocking run-start until region is set (lihat [phase-3-local-leaderboard-season.md](./phase-3-local-leaderboard-season.md))
- [ ] T3.2 — Extend precompute job to per-scope aggregation (kecamatan/kabupaten_kota/provinsi) (lihat [phase-3-local-leaderboard-season.md](./phase-3-local-leaderboard-season.md))
- [ ] T3.3 — Insufficient_data handling in precompute job (lihat [phase-3-local-leaderboard-season.md](./phase-3-local-leaderboard-season.md))
- [ ] T3.4 — Extend GET /api/leaderboard with scope filters (lihat [phase-3-local-leaderboard-season.md](./phase-3-local-leaderboard-season.md))
- [ ] T3.5 — Local leaderboard screen with scope filter UI (lihat [phase-3-local-leaderboard-season.md](./phase-3-local-leaderboard-season.md))
- [ ] T3.6 — Season lifecycle management (upcoming → active → ended) (lihat [phase-3-local-leaderboard-season.md](./phase-3-local-leaderboard-season.md))
- [ ] T3.7 — Season-scoped rank reset on transition (lihat [phase-3-local-leaderboard-season.md](./phase-3-local-leaderboard-season.md))
- [ ] T3.8 — Historical final rank retention after season ends (lihat [phase-3-local-leaderboard-season.md](./phase-3-local-leaderboard-season.md))
- [ ] T3.9 — Season info screen with countdown (lihat [phase-3-local-leaderboard-season.md](./phase-3-local-leaderboard-season.md))
- [ ] T3.10 — End-to-end verification: season close/open cycle (phase DoD gate) (lihat [phase-3-local-leaderboard-season.md](./phase-3-local-leaderboard-season.md))

## Fase 4 — Backlog (out of scope for now)
- [ ] T4.1 — Circle / Clan / Club (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.2 — Club War (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.3 — Matchmaking between circles (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.4 — Monetization: seasonal pass (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.5 — Monetization: advanced statistics (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.6 — Monetization: exclusive badge (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.7 — Monetization: premium profile (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.8 — B2B dashboard: running club (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.9 — B2B dashboard: event organizer (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.10 — Route map visualization (Mapbox) (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.11 — Android support (postponed indefinitely) (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.12 — Redis-backed real-time global leaderboard cache (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.13 — Native iOS platform integrations (Live Activities, Dynamic Island, HealthKit, WidgetKit) (lihat [phase-4-backlog.md](./phase-4-backlog.md))
