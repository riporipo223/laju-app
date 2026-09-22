# Phase 0 — Project Setup (no backend)

Source: [development-plan.md](../development-plan.md) Fase 0

Goal of this phase: prove background GPS tracking works reliably on a real
iOS device, with a repo scaffold in place — no backend, no point
calculation yet.

**Note on task numbering:** this phase was rewritten for the iOS/Swift
pivot (tech-spec.md §1). T0.1–T0.4 and T0.6–T0.9 keep their original IDs
(many cross-referenced elsewhere — T0.6 alone has 25 references across
other documents) with content rewritten for native tooling. **T0.5**
(previously: Android dev-client build) is removed outright rather than
repurposed — Android is postponed with no timeline (mvp-report.md §8), so
there is no Fase 0 Android work to replace it with. IDs are not
renumbered to avoid a large, error-prone cross-reference rewrite across
tasks/phase-1 through phase-3, tech-spec.md, and architecture.md for zero
substantive benefit.

---

### T0.1 — Init repo scaffolding (monorepo: `ios/` + `backend/`)

**Objective:** Establish the repo structure everything else builds inside,
per repo-coding-rules.md.

**Scope:**
- Yang dikerjakan: empty `ios/` and `backend/` directories, root
  `README.md`, `.gitignore` (Xcode + Node patterns), empty
  `shared/point-formula.fixtures.json` placeholder (`[]`) for the
  cross-language parity strategy (tech-spec.md §2.2b).
- Yang TIDAK dikerjakan: actual app code, actual backend code, CI pipeline
  config (separate concern, not blocking Fase 0).

**Depends on:** None

**Reference:** [repo-coding-rules.md](../repo-coding-rules.md) §1

**Definition of Done:**
- [x] Top-level layout (`ios/`, `backend/`, `shared/`, `Laju/documents/`)
      matches repo-coding-rules.md §1 — the inner structure of `ios/` and
      `backend/` is created by T0.2/T2.1, not this task
- [x] No root-level JS/pnpm/Turborepo config — `ios/` and `backend/` are
      independent build units (repo-coding-rules.md §1) — confirmed: no
      `package.json`/`pnpm-workspace.yaml`/`turbo.json` at repo root
- [x] `shared/point-formula.fixtures.json` exists as an empty placeholder
      (`[]`) — populated with real vectors by T1.1

---

### T0.2 — Init native Xcode project (Swift + SwiftUI, iOS 16 min)

**Objective:** Get a native iOS app booting, as the foundation for all
mobile work.

**Scope:**
- Yang dikerjakan: new Xcode project inside `ios/` (App template, SwiftUI
  lifecycle, Swift), deployment target set to iOS 16.0, app boots on iOS
  Simulator with default screen. Includes an `ios/LajuTests` XCTest target
  (empty, no tests yet — T1.1 is the first task to add tests to it) and
  Swift Package Manager wired as the dependency manager (no packages added
  yet — T2.3 is the first task to add one, the Supabase Auth Swift SDK).
- Yang TIDAK dikerjakan: physical device build/signing (T0.4), any real
  screens, Core Data model (T0.6), location setup (T0.7), any actual test
  or dependency content.

**Depends on:** T0.1

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §1 (Mobile client row),
[repo-coding-rules.md](../repo-coding-rules.md) §1 (folder tree),  §3
(Swift Strict Concurrency / warnings-as-errors baseline)

**Definition of Done:**
- [x] App builds and runs on iOS Simulator — verified on iPhone 17
      (iOS 26.3 runtime), via `xcodebuild test` (which builds + installs +
      launches on the simulator destination)
- [x] Deployment target confirmed at iOS 16.0 in project settings —
      `project.yml` `deploymentTarget: "16.0"`, confirmed in build logs
      (`target arm64-apple-ios16.0`)
- [x] `ios/LajuTests` XCTest target exists and runs (empty pass) in Xcode —
      target exists and runs; no longer empty as of T0.6 (2 tests, both
      passing) — this task's own bar (target exists, runs) is met, the
      "(empty)" description was just this task's starting state
- [x] SPM is the configured dependency manager (no CocoaPods/Carthage) —
      confirmed, no `Podfile`/`Cartfile`, XcodeGen project uses SPM
- [x] Swift Strict Concurrency / standard warnings-as-errors baseline
      enabled (no ad-hoc suppression) — per repo-coding-rules.md §3 —
      confirmed enabled in `project.yml`, and confirmed actually
      enforcing: it caught 2 real compile-time bugs during T0.8/T0.6 work
      (`Date?` unwrap, `@Sendable` closure capturing non-Sendable `self`)

---

### T0.3 — Configure SwiftLint/SwiftFormat across the iOS app

**Objective:** Enforce repo-wide lint/format rules from the start, not
retrofitted later.

**Scope:**
- Yang dikerjakan: add `.swiftlint.yml` and `.swiftformat` at `ios/` root
  per repo-coding-rules.md §3, wire as an Xcode Build Phase (or a
  `Makefile`/script target) so lint runs on build.
- Yang TIDAK dikerjakan: CI enforcement wiring (tracked separately, not a
  Fase 0 blocker but should exist before Fase 1 PRs land).

**Depends on:** T0.2

**Reference:** [repo-coding-rules.md](../repo-coding-rules.md) §3

**Definition of Done:**
- [x] `swiftlint` runs clean on the fresh app skeleton — `0 violations` on
      all 7 Swift files
- [x] `swiftformat --lint .` runs clean — `0/7 files require formatting`
- [x] Config matches repo-coding-rules.md §3 exactly (no ad-hoc rule
      overrides without reason)

---

### T0.4 — iOS build running on physical device

**Objective:** Confirm the app can be built, signed, and installed on a
real iOS device — required before background GPS testing (simulators are
unreliable for this).

**Scope:**
- Yang dikerjakan: Xcode signing/provisioning setup (Apple Developer
  Program enrollment — lean-canvas.md §7 cost item), install on at least
  one physical iOS device via direct Xcode deploy (TestFlight not required
  yet at this stage).
- Yang TIDAK dikerjakan: location/background capability config (T0.7),
  App Store/TestFlight distribution pipeline (later, not a Fase 0
  blocker).

**Depends on:** T0.2

**Reference:** tech-spec.md §1 (Mobile client row — background GPS
requires a physical device to verify regardless of tracking mechanism)

**Definition of Done:**
- [x] App installs and launches on a physical iOS device via direct Xcode
      deploy — verified repeatedly on an iPhone 13 (iOS 18.6.2) across this
      task's own testing and T0.9's device test, both via Xcode's own
      build/sign pipeline (`xcodebuild -allowProvisioningUpdates`) and
      `devicectl device install`/`process launch` (the CLI equivalent of
      Xcode's Run button, same underlying signing/install path)
- [x] Signing/provisioning steps documented in `ios/README.md` — includes
      the two real blockers hit and fixed: bundle id collision
      (`com.laju.app` was already registered to a different Apple
      Developer account — app ids are globally unique across ALL
      accounts, not just within one; moved to `com.designbyripo.laju`),
      and Developer Mode needing to be enabled on-device before
      `devicectl`/Xcode can install anything to it

---

### T0.6 — Set up local Core Data schema for runs (data/sync layer skeleton)

**Objective:** Create the local persistence layer that all offline
behavior depends on.

**Scope:**
- Yang dikerjakan: Core Data model (`.xcdatamodeld`) with a `Run` entity
  with two distinct groups of attributes:
  - **Locally-computed** (never touched by any server response):
    `id, startedAt, endedAt, distanceMeters, durationSeconds, gpsRoute,
    estimatedPoints`. `gpsRoute` stores an array of per-point `{lat, lng,
    timestamp, elevation}` samples (encoded as `Data`/Transformable or a
    related ordered entity — implementer's choice), not just lat/lng —
    required for server-side anti-cheat, tech-spec.md §2.1.
  - **Sync/server-mirror** (written once the run is submitted, and
    updated later by reconciliation, tech-spec.md §3 steps 4/5/7):
    `syncStatus` (`pendingSync|syncing|synced|failed` — **client-only**,
    no server counterpart), `serverRunId` (optional — the server's
    `run_id` from the `POST /api/runs` response, needed to correlate
    future `GET /api/runs?since=` results back to this row),
    `serverStatus` (optional — a **local cache** of the server's
    `RUN.status`: `validated|flagged|approved|rejected`; this is a
    completely different attribute from `syncStatus`, different value
    set, and does not exist until the first successful sync response),
    `flagConfidence` (optional, `low|high`), `anomalyFlags` (optional,
    JSON-encoded), `finalPointsAwarded` (optional), `resolvedAt`
    (optional).
  Also create a separate single-instance `SyncMeta` entity
  (`lastReconciledAt`, `lastReconcileAttemptAt`) — the reconciliation
  cursor and cadence anchor (tech-spec.md §3 step 7), deliberately not
  attributes on any `Run` row since they're global state, not per-run.
  `lastReconciledAt` advances only on a successful call;
  `lastReconcileAttemptAt` updates on every attempt (success or failure)
  and is what enforces the ≥15-minute cadence floor across app restarts.
- Yang TIDAK dikerjakan: sync queue logic itself (no server exists yet —
  that's T2.14), point calculation (Fase 1), the reconciliation call
  itself (T2.14d; the endpoint it calls is T2.14c) — this task only
  creates the entity/attributes those later tasks read and write.

**Depends on:** T0.2

**Reference:** [architecture.md](../../02-architecture/architecture.md) §3 (Data/Sync layer),
[database-api-spec.md](../../02-architecture/database-api-spec.md) §1 (Run entity),
[tech-spec.md](../../02-architecture/tech-spec.md) §3

**Definition of Done:**
- [x] `NSPersistentContainer` loads the `Run` and `SyncMeta` entities on
      app first launch (Core Data model versioned for future migrations) —
      confirmed both via `PersistenceTests` (XCTest, simulator) and 13 real
      `Run` rows accumulated in the on-device SQLite store across T0.9
      testing
- [x] `SyncMeta` has exactly one instance holding both `lastReconciledAt`
      and `lastReconcileAttemptAt` (both optional/nil initially) —
      `testSyncMetaSingleInstance` (XCTest) confirms `syncMeta(in:)`
      returns the same instance on repeated calls. Note: real on-device
      usage never exercises this path yet (`ZSYNCMETA` has 0 rows on the
      device — nothing calls `syncMeta(in:)` outside the test, since the
      reconciliation feature that would is T2.14d/Fase 2) — this DoD item
      is satisfied by the test, not by organic app usage
- [x] A hand-written test `Run` object can be inserted and fetched back
      correctly via `NSManagedObjectContext` — `testRunInsertAndFetch`
      (XCTest) passes; also demonstrated by real app usage (13 `Run` rows
      inserted/fetched via the actual UI, inspected directly in the
      on-device SQLite store during T0.9 testing)
- [x] Locally-computed attributes match database-api-spec.md Run entity
      for the fields they share; `syncStatus` is confirmed distinct from
      `serverStatus` (two different attributes, two different value sets)
      — confirmed directly against the SQLite schema (`ZSYNCSTATUS` vs
      `ZSERVERSTATUS`, separate columns) and observed data (`syncStatus`
      populated on every row, `serverStatus` untouched/null on all of
      them, since nothing has synced to a server yet — Fase 2)

**Bug found + fixed during this verification** (not part of the original
scope, but caught running `PersistenceTests` on simulator for the first
time): `PersistenceController` originally called
`NSPersistentContainer(name: "Laju")`, which re-derives/re-parses the Core
Data model on every `init`. When more than one `PersistenceController`
exists in the same process (the test host app's own `.shared` alongside a
test's `PersistenceController(inMemory: true)`), each got a distinct
`NSManagedObjectModel` object from re-parsing the same file, and Core
Data's dynamic `+entity` class-to-entity resolution can't disambiguate
between them — logged as `CoreData: error: +[Run entity] Failed to find a
unique match...`, present even after a clean build. Fixed by parsing the
model exactly once into a cached `static let`, reused by every
`PersistenceController` instance (`PersistenceController.swift`). Tests
pass cleanly (0 warnings) after the fix.

---

### T0.7 — Integrate `CLLocationManager` (permissions, background config)

**Objective:** Wire in native location tracking that all tracking depends
on.

**Scope:**
- Yang dikerjakan: `CLLocationManager` setup, `Info.plist` entries
  (`NSLocationWhenInUseUsageDescription`,
  `NSLocationAlwaysAndWhenInUseUsageDescription`, `UIBackgroundModes` →
  `location`), `allowsBackgroundLocationUpdates = true`,
  `pausesLocationUpdatesAutomatically = false` (correction 2026-09-13,
  Round 7 finding N7-6 — as shipped, stop-detection is deliberately
  handled by explicit pause/resume, T1.2b/T1.11, not this iOS-native
  flag), minimal delegate callback logging GPS points to console.
- Yang TIDAK dikerjakan: UI, persistence to Core Data (T0.8), point
  calculation.

**Depends on:** T0.4

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §1 (GPS tracking row), §4
(battery — `desiredAccuracy`/`distanceFilter`)

**Definition of Done:**
- [x] Location permission prompts appear correctly (when-in-use, then
      always-allow upgrade flow) — verified live on iPhone 13 (When-In-Use
      prompt on first launch, Always-upgrade prompt on Start tap once
      When-In-Use already granted — this two-step ordering had to be
      fixed: an early version requested Always directly on first tap,
      which iOS doesn't reliably honor before When-In-Use is already
      granted, see `RunTrackingView.swift`)
- [x] GPS points log to console while app is in foreground on a physical
      device — **PASSED, live-verified.** `devicectl device process
      launch --console` attached to a fresh launch on iPhone 13; 4 real
      GPS points printed over a ~2-minute foreground session:
      ```
      LocationTrackingService: lat=-7.705688839136416 lng=110.40836081279356 alt=271.59569622039794 t=2026-09-10 09:48:36 +0000
      LocationTrackingService: lat=-7.705688839136416 lng=110.40836081279356 alt=271.59569622039794 t=2026-09-10 09:48:50 +0000
      LocationTrackingService: lat=-7.705741201270451 lng=110.40826674565804 alt=271.90491705574095 t=2026-09-10 09:50:19 +0000
      LocationTrackingService: lat=-7.705738095299134 lng=110.40828590821637 alt=271.8732046633959 t=2026-09-10 09:50:24 +0000
      ```
      (First console-attach attempt hit the same tunnel-drop issue seen
      elsewhere in T0.9 testing — device idle for a moment invalidated the
      CoreDevice connection mid-stream; retried with the device kept awake
      and it held for the full capture window.)
- [x] Background location updates verified: locking the screen with an
      active `CLLocationManager` session still delivers updates —
      verified: ~59 minutes continuous, points/distance kept incrementing
      while the screen was locked (T0.9 test)

---

### T0.8 — Basic start/stop run UI persisting raw GPS trail to Core Data

**Objective:** Connect `CLLocationManager` to local storage — the first
end-to-end "a run happened and was saved" slice.

**Scope:**
- Yang dikerjakan: minimal SwiftUI screen with Start/Stop button (View +
  ViewModel, MVVM). **The `Run` managed object is created and saved to
  Core Data at Start** (`startedAt` set, `syncStatus = pendingSync` —
  client-only field, tech-spec.md §3, not the server's `RUN.status`), and
  incoming GPS points (each retaining `timestamp` and `altitude`/elevation
  from `CLLocation`, not just lat/lng — tech-spec.md §2.1) are appended
  and the context saved incrementally while the run is active (e.g. every
  N points or T seconds — implementer's choice, not a fixed requirement
  here), **not only once at Stop** — this is what makes T0.9's force-kill
  DoD meaningful: writing everything only on Stop would mean a run killed
  mid-track has no row to recover at all. On Stop, `endedAt`,
  `distanceMeters`, `durationSeconds` are finalized and saved.

  **Correction (2026-09-13, Round 7 finding B7-2/B7-P1):** only
  `gpsRoute`/`distanceMeters` are saved incrementally while active —
  `durationSeconds` as shipped is written only in `pause()`/`stop()`
  (T1.2b), not incrementally. A crash mid-active-segment (never paused)
  therefore leaves a recovered row with `durationSeconds = 0`. T1.14
  (Fase 1, crash/interrupt recovery) now owns adding incremental
  `durationSeconds` persistence — this task's own DoD below (verified at
  the time against `distanceMeters`/`gpsRoute` only) is unaffected and
  stays accurate for what it actually asserts.
- Yang TIDAK dikerjakan: point calculation, run history screen (Fase 1),
  any styling polish.

**Depends on:** T0.6, T0.7

**Reference:** [architecture.md](../../02-architecture/architecture.md) §2 steps 1–2

**Definition of Done:**
- [x] A run started and stopped on a physical device produces a `Run`
      object with a non-empty GPS trail — confirmed: several normal
      start/stop runs on-device, each with a non-null, valid `gpsRoute`
      inspected directly in the on-device SQLite store
- [x] `distanceMeters` and `durationSeconds` are computed correctly
      against a known test route (manual verification, within reasonable
      GPS tolerance) — **PASSED, cross-validated against Strava running
      in parallel on the same device for the same outdoor jog** (iPhone
      13, iOS 18.6.2, 2026-09-11 21:13-21:15 WIB): Laju recorded 660.90m,
      Strava recorded 660m (0.66km) — **~0.15% deviation**. Verified
      beyond the aggregate number: all 50 consecutive point-pairs in the
      raw `gpsRoute` were recomputed independently (haversine) and none
      exceed the 12 m/s implausible-speed threshold (max 10.46 m/s), and
      an explicit check for a "jump immediately cancelled by a reverse
      jump" pattern (which would make a corrupted route's total look
      coincidentally clean) found none. This is a stronger verification
      method than a single manual tape-measured route — a live third-party
      GPS reference plus raw-data inspection catches both magnitude errors
      *and* errors that only look correct in aggregate; worth reusing for
      any future distance-accuracy validation (e.g. a longer route before
      release). Two earlier rounds of real bugs were found and fixed
      getting here (see repo history / RunViewModel.swift,
      LocationTrackingService.swift): (1) no accuracy/staleness/speed
      filtering at all — a cold GPS fix produced a 6459 km/h implied-speed
      jump; (2) speed filtering alone wasn't sufficient — GPS jitter
      oscillating within a fix's own accuracy radius summed to a false
      33m over a <10m real walk, fixed with a minimum-movement floor
      relative to `horizontalAccuracy`.
- [x] Incremental saves during an active run are verified directly against
      the Core Data store (not just the final Stop write) — this is the
      behavior T0.9's force-kill test depends on — verified repeatedly:
      live pulls of the on-device SQLite store mid-run (before any Stop)
      showed non-null `gpsRoute` data already written, both via the
      count-based (20-point) and time-based (30s) triggers

---

### T0.9 — Verify background tracking survival + battery benchmark (phase DoD gate)

**Objective:** Confirm Fase 0's actual acceptance bar from
development-plan.md is met before moving to Fase 1. This is the spike that
was previously gated on validating a third-party background-geolocation
library's reliability; with native `CLLocationManager` (no third-party
risk layer), this task instead directly validates the SwiftUI skeleton +
`CLLocationManager` combination itself on real hardware — the DoD purpose
(background survival, battery, force-kill data safety) is unchanged.

**Scope:**
- Yang dikerjakan: run a ≥60-minute test with screen off / app
  backgrounded on one physical iOS device; measure battery drain; confirm
  GPS trail is not lost if the OS kills the app.
- Yang TIDAK dikerjakan: any new feature — this is a verification task
  only, fixes go back into T0.7/T0.8 if the benchmark fails. No Android
  device test — Android is postponed (mvp-report.md §8).

**Depends on:** T0.8

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §4 (battery target
<5%/hour), [development-plan.md](../development-plan.md) Fase 0 DoD

**Environment prerequisite (verify before starting):** full Xcode.app
installed (not just Command Line Tools — `xcode-select -p` should point
inside `Xcode.app/Contents/Developer`), and a physical iOS device
connected/paired and trusted. Simulator (`xcrun simctl`) cannot substitute
— background suspension/termination behavior does not reproduce reliably
in the simulator.

**Definition of Done:**
- [x] Background tracking survives while backgrounded (screen locked, other
      apps in use) on a physical iOS device — **PASSED**: iPhone 13, iOS
      18.6.2, ~59 minutes continuous (13:46–14:45), GPS points/distance
      kept updating throughout (0→8 points, 0→46m) while the screen was
      locked and the device was used for other apps (camera, video,
      hotspot). Process was never killed by the OS during this window.
- [x] GPS capture pipeline verified end-to-end on device — **PASSED**:
      "Always" location authorization granted via the two-step prompt
      flow (When-In-Use → Always upgrade), points/distance visibly
      incrementing live in the UI and confirmed against the on-device
      Core Data store.
- [x] Force-kill test: run data recorded up to the last incremental save
      before kill (T0.8) is not lost (row still present in Core Data) —
      **PASSED, after a fix.** First attempt (count-only incremental save,
      every 20 points) FAILED: an 8-point session never reached the
      20-point threshold, so nothing had been flushed to Core Data before
      the kill — confirmed both by the app's own UI and directly against
      the on-device SQLite store (`ZRUN.ZGPSROUTE` was `NULL`). Root cause:
      the incremental-save trigger was count-based only, with no fallback
      for a low-activity session. Fixed by adding a second, independent
      time-based flush trigger (every 30s of wall time, alongside the
      existing 20-point trigger — see `RunViewModel.swift`,
      `flushIntervalSeconds`). Re-verified twice directly against the
      on-device SQLite store (not just the UI, which has no
      resume-after-relaunch display and will show 0 on next launch
      regardless of what's actually persisted — a separate UX gap, not a
      data-loss bug, now owned by T1.14 (Fase 1, crash/interrupt recovery,
      2026-09-13)): once via a live pull mid-run (a still-
      running, un-stopped session already had a non-null `gpsRoute` on
      disk), and once via a post-kill pull confirming that same row's data
      was untouched by the kill.
- [x] Battery draw < 5%/hour — **PASSED, clean retest.** iPhone 13, iOS
      18.6.2, phone unplugged and locked/idle (no other heavy app use)
      for the full window: **49%→46% over 60 minutes = 3%/hour**, under
      the <5%/hour target. Supersedes the earlier contaminated datapoint
      (62%→39%/55min, ≈25%/hour — that run included camera/video/hotspot
      usage and was never valid evidence, only ever logged as such).
- [x] Results documented (device model, iOS version, battery %, route) for
      future reference — iPhone 13, iOS 18.6.2, 2026-09-11: background
      survival ~59min, GPS pipeline verified, force-kill integrity
      verified, battery 49%→46%/60min (3%/hour)
- [ ] Raw GPS trail(s) from the test run(s) exported/retained in the
      `gps_route` point format (`{lat, lng, timestamp, elevation}`) for
      reuse as genuine-route fixtures by T2.6b — **not yet done**, pending

**Second bug found + fixed during the battery retest** (the run that
produced the 3%/hour number stayed active the whole time, so it doubled as
an unplanned stationary test): the phone sat indoors, completely still,
for the full 60 minutes, yet the run recorded 4 GPS points and 34.9m of
distance. Traced to raw data (`pk=41`): three segments of 14.32m, 14.32m,
and 6.25m, none exceeding the 12 m/s speed filter or the per-step
accuracy-based jitter floor added after the first GPS bug (see T0.8's
history above) — each step looked individually plausible relative to the
point right before it. The floor only guards against one big jump; it
doesn't stop the *reference point itself* drifting away from the phone's
true (stationary) position one small step at a time. Fixed with a
`stationaryAnchor` in `RunViewModel.swift`: distance is now judged against
the last point confirmed as real movement, not just the previous accepted
point, and a step within 20m of that anchor is recorded (raw trail stays
complete) but not counted toward distance and does not move the anchor.
Documented in tech-spec.md §2.1b so this isn't lost track of.

**RESOLVED (2026-09-12), with a documented limitation.** Retest: a single
continuous 61.8-minute stationary session (indoor), `distanceMeters`
stayed at 0m throughout — well past the ≥35min bar. The planned outdoor
phase never produced a second GPS point before Stop, so the
`stationaryAnchor` radius-check itself was never actually exercised in
this retest (no point ever arrived close enough to the anchor to need
evaluating) — the result is strong practical evidence (an hour stationary
produces zero phantom distance) but not a direct test of the anchor logic
itself. A first attempt at this retest (~6.3min, 1 point) wasn't long
enough and had to be redone with explicit clock targets. If the anchor
mechanism itself needs direct verification later, hold the device in hand
with small natural movement rather than leaving it flat on a surface —
that's what would actually generate the in-radius drift points needed to
exercise the check. See tech-spec.md §2.1b for full detail.

---

### T0.10 — CI: path-filtered lint/format/test pipeline (`ios/` + `backend/`)

**Objective:** Give repo-coding-rules.md §3's "PRs cannot merge with lint
failing" and T2.13's "test suite is part of CI, not a one-off manual run"
DoD an actual pipeline to point at — neither existed as an owned task
before this addition, despite both other documents assuming one.

**Scope:**
- Yang dikerjakan: two path-filtered CI jobs (`ios/**` → SwiftLint +
  SwiftFormat + `xcodebuild test`; `backend/**` → ESLint + Prettier +
  test runner), per repo-coding-rules.md §1/§3. Runs on every PR.
- Yang TIDAK dikerjakan: deployment/release automation (separate concern,
  not a Fase 0 blocker).

**Depends on:** T0.3 (iOS job can be built once this lands); the backend
job's target doesn't exist until T2.1 (Fase 2) — this task's iOS half
ships in Fase 0, its backend half is completed alongside T2.1, not
re-tracked as a separate task.

**Reference:** [repo-coding-rules.md](../repo-coding-rules.md) §1, §3

**Definition of Done:**
- [x] A PR touching only `ios/**` triggers the iOS job, not the backend
      one, and vice versa — **PASSED, both directions confirmed live on
      GitHub Actions.** Initial design only had `if: false` on the
      backend job (not real path filtering — a change outside `ios/`
      would still trigger the iOS job) — split into `ci-ios.yml`
      (`paths: ios/**`) and `ci-backend.yml` (`paths: backend/**`).
      Verified: a push touching only `ios/` triggered `CI (iOS)` and not
      `CI (Backend)`; a later push touching neither path (just the
      backend workflow's own trigger config) triggered **neither**
      workflow, confirming the filter is real, not coincidental.
- [x] Lint/format failure on either side blocks merge (CI red) — the
      mechanism itself is standard GitHub Actions behavior (any non-zero
      step exit fails the job), and was directly observed: the first real
      CI run failed (a bad `xcodebuild` destination, see below) and
      showed as `Failure` on GitHub, not silently green. Not separately
      re-tested with a deliberate lint violation — the failure path is
      the same mechanism regardless of which step trips it.
- [x] `ios/LajuTests` (T0.2) and the backend test runner both execute in
      CI, not just locally — `xcodebuild test` runs `LajuTests` as part
      of the iOS job, confirmed passing on GitHub Actions (run
      [34678173791](https://github.com/riporipo223/laju-app/actions/runs/34678173791)).
      Backend test runner doesn't exist yet (T2.1, Fase 2) — its workflow
      is wired and path-filtered, but has nothing to execute until then.

**Two real bugs found + fixed verifying this task:**
1. **Hardcoded simulator name.** `xcodebuild -destination
   'platform=iOS Simulator,name=iPhone 16'` failed on the `macos-15`
   GitHub runner — `iPhone 16` isn't a provisioned simulator on that
   image (only generic placeholder destinations were listed available).
   Fixed by discovering an available iPhone simulator's UDID dynamically
   via `xcrun simctl list devices available -j`, instead of hardcoding a
   device name that varies by runner image/Xcode version.
2. **Path filtering wasn't real.** The original single `ci.yml` used
   `if: false` to disable the backend job — not `paths:` filtering. A
   backend-only (or unrelated) change would still have triggered the iOS
   job to run needlessly. Split into two workflow files
   (`ci-ios.yml`/`ci-backend.yml`), each with its own `paths:` trigger,
   matching repo-coding-rules.md §1's actual stated design.
