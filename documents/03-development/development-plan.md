# Laju App — Development Plan (v1)

Depends on: [product-spec.md](../01-product/product-spec.md), [tech-spec.md](../02-architecture/tech-spec.md),
[architecture.md](../02-architecture/architecture.md), [database-api-spec.md](../02-architecture/database-api-spec.md)

Order follows mvp-report.md's agreed strategy: validate the single-player
core loop before any backend/leaderboard investment.

## Fase 0 — Project Setup (no backend)

**Scope:**
- Init native Xcode project (Swift + SwiftUI, min. iOS 16) — no
  cross-platform framework, no dev-client concept (that was an Expo/RN-era
  term).
- Set up `CLLocationManager` (native, `allowsBackgroundLocationUpdates`),
  get a real background track working on a physical **iOS** device
  (simulators are unreliable for GPS background behavior — this is a
  physical-device requirement regardless of tracking mechanism, see T0.9).
- Init Core Data model: `Run` entity (locally-computed attributes) plus
  the sync/server-mirror attributes and the `SyncMeta` reconciliation
  cursor entity those attributes need later (T0.6 — no sync *logic* yet,
  Fase 2 territory; this phase only creates the entity/attributes).
- Repo scaffolding per [repo-coding-rules.md](./repo-coding-rules.md)
  (monorepo, `ios/` + `backend/`).

**Definition of Done:**
- App can start/stop a run and record a GPS trail to local Core Data while
  backgrounded, on a physical iOS device.
- Battery draw measured against tech-spec §4 target (<5%/hour) on at least
  one real iOS device.
- Local schema includes the sync/server-mirror attributes and `SyncMeta`
  entity (T0.6) — empty/unpopulated in this phase (no backend to sync
  with yet), but present so Fase 2 doesn't need a schema migration to
  add them later.

**Dependency note:** nothing here blocks on backend — this phase is
intentionally backend-free. Android is postponed with no timeline (Future
Development, see lean-canvas.md/mvp-report.md) — no Android work in this
phase or any scheduled phase.

## Fase 1 — Core Loop Offline

**Scope:**
- Implement point calculation formula + pace multiplier locally
  (tech-spec §2.2–2.3), computed entirely on-device.
- Local level progression (derived from local cumulative points, no
  server).
- Run history screen (local data only).
- No anti-cheat yet at this stage — there is no shared leaderboard to
  protect, only local single-player state.
- **9 items added 2026-09-12** (product-spec.md §4.8-4.16, tech-spec.md
  §5) — found via a deliberate sweep for implicit requirements (App Store
  standards, competitor baseline, consistency with Laju's own defined
  personas) that the original breakdown missed, not new scope creep. All
  client-only, no backend needed: live map during tracking + static route
  map on Summary/History (MapKit, reverses the prior "route map" Non-goal
  — see tech-spec.md §5.1), splits per kilometer, ~~auto-pause (reusing the
  existing `stationaryAnchor` drift guard as an explicit user-facing
  trigger, not new detection logic)~~ **[removed 2026-09-22, PM sign-off —
  see product-spec.md §4.11 and tasks/phase-1-core-loop-offline.md T1.11;
  the reused `stationaryAnchor` drift guard itself was NOT removed, only
  its use as a pause trigger]**, elevation gain/loss, audio cues
  (`AVSpeechSynthesizer`), crash/interrupt recovery flow, refined location
  permission handling (While Using vs Always vs Denied), and a local
  streak-reminder notification (`UNUserNotificationCenter`, no server —
  streak is already tracked on-device since T1.1/T1.4). Now **8 items**
  after the auto-pause removal. See tasks/phase-1-core-loop-offline.md
  T1.8-T1.16 for the full breakdown.

**Definition of Done:**
- A user can complete multiple runs fully offline and see points/level
  progress accumulate correctly and consistently with the formula in
  tech-spec.md.
- This is the first point at which the core hypothesis in product-spec §1
  ("progression without social features is rewarding") becomes testable —
  internal dogfooding should start here, before backend exists.
- The 8 remaining items added 2026-09-12 (live map, static map, splits,
  elevation, audio cues, crash recovery, permission-flow refinement,
  streak reminder — auto-pause **removed 2026-09-22**, PM sign-off) all
  work correctly together during that same dogfood pass, not just
  individually (added 2026-09-13, Round 7 finding N7-P7 — T1.17's DoD
  already required this; this phase-level DoD is the source T1.17 cites
  and needed the same bullet).

**Dependency note:** the point formula implemented here must be identical
to what ships server-side in Fase 2 — since client (Swift) and server
(TypeScript) can no longer share one literal source file, parity is kept
via a shared test-fixture file (`shared/point-formula.fixtures.json`,
tech-spec.md §2.2b) instead. Divergence here is still the single biggest
risk of client/server point mismatches later — the fixture test is what
catches it now.

## Fase 2 — Backend + Sync + Global Leaderboard

**Scope:**
- Stand up Next.js API + Postgres (Supabase) per tech-spec §1.
- Supabase Auth integration (sign up/in from mobile).
- Minimal `Season` entity: schema (part of core migration) + one seeded
  `active` row — enough for `PointTransaction.season_id` and leaderboard
  precompute to have a season to scope to. Full lifecycle management
  (`upcoming → active → ended` transitions) is explicitly deferred to
  Fase 3 — this phase only needs a season to exist, not to change state.
- Minimal region validation, mirroring the Season pattern above: schema
  (`USER.region_*`, already part of core migration) + basic presence
  validation on `POST /api/profile/complete` (all 3 region fields
  required, non-empty) + a basic `409 Conflict` guard on `POST /api/runs`
  for users with no region set at all. This is the backend guarantee
  needed for `POST /api/runs` and the global leaderboard to function
  correctly starting this phase. Full onboarding UX (client-side
  pre-submission blocking) is Fase 3 (T3.1); per-region leaderboard
  granularity is **~~deferred to Fase 4 / v1.1~~ CANCELLED PERMANENTLY,
  2026-09-22** (decided 2026-09-21, reversed 2026-09-22, see Fase 3 and
  Fase 4 below) — this phase only needs "does this user have a
  region", not "is this region a valid catalog entry" or "does the UI stop
  them early". **Historical description, superseded**: region validation
  itself (the `409` guard, `USER.region_*` schema) is being removed
  entirely, not merely left unused — see database-api-spec.md.
- `LEADERBOARD_SCOPE` schema (part of core migration, alongside
  `LeaderboardEntry`) — migrated here because the global leaderboard needs
  an explicit `scope_type='global'` row from the start
  (database-api-spec.md §1). Only the global row is used in v1; the
  regional columns/`scope_type` values ~~are prepared for the deferred Local
  Leaderboard~~ **were prepared for Local Leaderboard (tasks T3.2–T3.5 in
  tasks/phase-4-backlog.md), which is cancelled permanently as of
  2026-09-22 — these regional columns/values are being dropped, see
  database-api-spec.md.**
- A dedicated GPS test fixture corpus (spoofed vs. real runs), built
  **before** the anti-cheat checks that consume it — see hard dependency
  below.
- Implement `POST /api/runs` with **full anti-cheat validation** (tech-spec
  §2.4) including the flagged→approved/rejected resolution flow
  (tech-spec §2.4.1) — this is not optional or deferred; see hard
  dependency below. Includes the `resolve-flagged-runs` scheduled job
  that actually performs the LOW-confidence auto-approve (tech-spec
  §2.4.1) — the resolution *logic* alone has no effect without this job
  registered and running.
- Sync queue on mobile (tech-spec §3).
- `PointTransaction` ledger + `User.total_points`/`current_level` derived
  from it.
- **Status reconciliation** (tech-spec §3 step 7, database-api-spec
  §2.2b): a `flagged` run's *later* resolution (LOW auto-approve up to
  48h afterward, HIGH at an arbitrary later time via manual override)
  happens after the run is already synced — the initial `POST /api/runs`
  response cannot carry it. This needs its own local schema (server-mirror
  attributes on the mobile `Run` Core Data entity plus a `SyncMeta`
  reconciliation cursor entity, T0.6), its own server column
  (`Run.updated_at`, T2.2) to filter on, its own
  endpoint (`GET /api/runs?since=`, T2.14c), its own client polling/
  cursor loop (T2.14d), and its own client display logic (T2.14b) —
  designed as one unit, not layered in piecemeal, after 4 rounds of
  audit found the next missing piece each time a narrower fix was
  applied. Explicitly gated into this phase's completion (T2.21) so it
  cannot be silently skipped.
- Global `LeaderboardEntry` precompute job (architecture.md §4) — only
  `validated`/`approved` runs contribute, `flagged`/`rejected` are
  excluded until resolved — global leaderboard screen.
- **Account deletion (added 2026-09-12, product-spec.md §4.17) — MANDATORY,
  release blocker, not optional.** App Store Guideline 5.1.1(v) requires
  in-app account deletion for any app with account creation, and only
  becomes buildable once this phase's auth (T2.3) exists. See
  tasks/phase-2-backend-sync-global-leaderboard.md T2.22 and
  pre-launch-checklist.md.

**Definition of Done:**
- A run recorded offline syncs correctly once online, server-validated
  points match (or correctly diverge with a visible reason) from the local
  estimate.
- Anti-cheat checks are active and demonstrably catch at least the pace-cap
  and GPS-speed-jump cases, tested against the dedicated fixture corpus
  (not ad-hoc data written by whoever implemented the check).
- A `flagged` run's points do not appear on the global leaderboard until
  auto-resolved to `approved` (or the resolution transitions it to
  `rejected`, in which case they never appear).
- A `flagged` run's later resolution (auto or manual) is reflected in the
  mobile client within one reconciliation cycle — the "visible reason"
  half of the DoD's first bullet is not satisfied by the initial sync
  response alone.
- Global leaderboard is queryable and reflects precomputed data within the
  15-minute freshness target.
- User can delete their account entirely from within the app (product-spec
  §4.17) — this item is a release blocker independent of the leaderboard
  hard dependency below; App Store submission cannot proceed without it
  once auth exists, regardless of leaderboard/anti-cheat status.

**Hard dependency (do not violate):** anti-cheat must ship and be verified
**before** the global leaderboard is made visible to users. A leaderboard
opened before anti-cheat exists gets gamed immediately and the resulting
bad data/reputation damage is hard to undo — this ordering is a
correctness requirement, not a nice-to-have.

## Fase 3 — Season System

> **Scope change, 2026-09-21:** this phase used to be "Local Leaderboard
> Granular + Season System". The Local Leaderboard was **cut from MVP v1**
> and ~~moved to Fase 4 / v1.1 (deferred, not cancelled): it only becomes
> useful once user density is high — with few early users a kecamatan
> holds a handful of people and the board is empty/uncompetitive, while a
> Global board already feels "local" at small scale.~~ The Global Leaderboard
> is fully built in Fase 2 (T2.18–T2.20), so this phase is now **Season
> only** (plus T3.1, the region-onboarding UX — **removed as of 2026-09-22,
> see below**). The former T3.2–T3.5 keep their IDs and full detail in
> tasks/phase-4-backlog.md.
>
> **Update 2026-09-22 (PM sign-off): Local Leaderboard CANCELLED
> PERMANENTLY, not deferred.** Rationale: scope too broad for the
> leaderboard logic needed. T1's already-shipped, signed-off T3.1
> (region-onboarding UX) is being reworked to remove the region step
> entirely — see tasks/phase-3-season.md T3.1 and product-spec.md §4.1 D1
> reversal / §4.5 AC5 for the replacement location-permission-gate
> mechanism.

**Scope:**
- ~~Mobile onboarding UX that blocks the run-start flow client-side before
  a wasted network call (kecamatan/kabupaten_kota/provinsi, product-spec
  AC 4.1.2) — the backend `409` guard itself already shipped in Fase 2
  alongside minimal region validation; this phase adds the client-side
  experience on top of it, not the guarantee itself. Region is collected
  in v1 even though no v1 screen uses it yet (prepared data for the
  deferred Local Leaderboard; mandatory by final decision D1, 2026-09-21, product-spec.md §4.1).~~
  **Superseded 2026-09-22**: this was T3.1's original, shipped, signed-off
  scope (Fase 3 DONE 2026-09-22). D1 is reversed — region is no longer
  collected at all. T3.1 is being reworked to remove the region step
  entirely and gate Leaderboard visibility on location permission instead
  (product-spec.md §4.1/§4.5 AC5).
- Full Season lifecycle (`upcoming → active → ended` transitions) added
  on top of the minimal seeded season from Fase 2 — season-scoped rank
  reset of the **global** leaderboard (lifetime points/level untouched).
- Season League derivation (T3.7a, added 2026-09-21): the meaning of "tier" in the Premium leaderboard AC — Bronze/Silver/Gold/Platinum from points earned this season, reset each season (tech-spec.md §2.5). Filtering the leaderboard by league / Premium gating stays Fase 4.
- Season info screen + countdown.

**Definition of Done:**
- A season can be closed and a new one opened without corrupting lifetime
  user points/levels; the global leaderboard starts fresh for the new
  season; historical final rank is retained per product-spec AC 4.7.3.

**Dependency note:** this phase depends on Fase 2's anti-cheat and global
precompute (T2.18) already being solid — season rank reset re-scopes that
same job to a new `season_id`.

## Fase 4 — Backlog (not scheduled, do not build yet)

- ~~**Local Leaderboard** (kecamatan / kabupaten-kota / provinsi, with the
  "belum cukup data" state) — **moved here from Fase 3 on 2026-09-21**;
  deferred to v1.1, not cancelled. Trigger to schedule it: enough active
  users per region for a regional board to be non-empty. Already prepared,
  not to be redone: the region hierarchy on `User`, the `LEADERBOARD_SCOPE`
  table and `scope_type` values (database-api-spec.md §1), and fully written
  tasks T3.2–T3.5 (tasks/phase-4-backlog.md, IDs kept so existing
  references stay valid). Product-spec §4.6 keeps its three AC as the spec.~~
- **Local Leaderboard: CANCELLED PERMANENTLY, 2026-09-22** (PM sign-off) —
  not deferred, will not be scheduled. Rationale: scope too broad for the
  leaderboard logic needed. The region hierarchy on `User` and
  `LEADERBOARD_SCOPE`'s regional `scope_type` values are being dropped from
  the schema, not kept prepared (database-api-spec.md). Tasks T3.2–T3.5
  (tasks/phase-4-backlog.md) and product-spec.md §4.6's three AC are kept
  struck through as historical record only.
- ~~Circle~~ Club (renamed 2026-09-23), matchmaking (product-spec §5
  Non-goals). Club War specifically **confirmed to build 2026-09-23**
  (product-spec.md §4.19) — still Fase 4/not v1. ~~only the shape is now
  partly decided.~~ **Mechanism finalized 2026-09-23** (§4.19 AC1-AC12) —
  Participation Rate win condition, 48-hour duration, targeted
  challenge/invite start, tie-break + forfeit rules. **AC7 resolved
  2026-09-23**: a declined/timed-out challenge produces zero Club War
  Record entry for anyone — fully unblocked, no open points left.
- Social Feed (post achievements, comments) — added 2026-09-12, previously
  only an unreconciled draft in user-flow.md; recommended here (not Fase
  3) for the same "prove the loop alone first" reasoning as Club above
  — see product-spec.md §5, tasks/phase-4-backlog.md T4.15-T4.16.
- Monetization: seasonal pass, advanced statistics, exclusive badges,
  premium profile (pricing decided 2026-09-23: $7.99/mo + App Store
  Connect regional tiers, product-spec.md §5; monthly only, no annual,
  no trial in v1 — all of these depend on T4.20, Premium subscription
  infrastructure, which does not exist yet — product-spec.md §4.23),
  B2B dashboard for clubs;
  ~~EO reframed as a managed service, not a dashboard (ADR-0014,
  lean-canvas.md §2/§6)~~ **concept replaced 2026-09-23 — Laju Branded
  Events** (product-spec.md §4.21, lean-canvas.md §2/§6): brand-sponsored
  or announcement-only Events, Laju staff-only creation, sponsorship-fee
  revenue, no region filter — still all Fase 4/not scheduled.
- ~~Route map visualization (Mapbox integration)~~ — **moved to Fase 1,
  2026-09-12** (MapKit, not Mapbox — see Fase 1 scope above, tech-spec.md
  §1/§5.1). No longer backlog.
- Apple Watch companion app — added 2026-09-12, ~~low priority/large
  effort~~ **confirmed to build 2026-09-23**, Apple Watch first then
  Garmin/Huawei (tasks/phase-4-backlog.md T4.14). Apple Watch v1 shape
  finalized 2026-09-23 (product-spec.md §4.22): mirror-only, live
  metrics + pause/stop, no start from the watch. Garmin/Huawei unscoped.
- Android support — postponed indefinitely, no timeline (mvp-report.md,
  tech-spec.md §1 — platform pivot decision, not a tech-debt item).
- Live Activities, Dynamic Island, HealthKit, WidgetKit integration —
  native-only capabilities newly available post-pivot, explicitly not v1
  scope (tech-spec.md §1).
- Redis-backed real-time global leaderboard (architecture.md §4 Open
  Question).

This phase exists in the plan only to make explicit that these items are
known and deliberately deferred — not forgotten.
