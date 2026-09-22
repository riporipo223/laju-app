# Phase 1 — Core Loop Offline

Source: [development-plan.md](../development-plan.md) Fase 1

Goal of this phase: make the single-player loop (run → points → level)
fully work offline, on-device, with the point formula matched against a
shared fixture file so Fase 2's server implementation cannot silently
diverge from it.

---

### T1.1 — Implement `calculatePoints` in `ios/Laju/PointFormula` with XCTest

**Objective:** Create the client-side point calculation, parity-checked
against the server's implementation — the top risk called out in
development-plan.md Fase 1→2 is client/server formula divergence. Since
Swift (client) and TypeScript (server) can no longer literally share one
source file post-pivot, parity is enforced via a shared test fixture
instead (tech-spec.md §2.2b) — this task is the client half of that.

**Scope:**
- Yang dikerjakan: `ios/Laju/PointFormula/PointFormula.swift` —
  `calculatePoints(distanceKm:avgPaceSecPerKm:streakDays:)` pure function
  implementing the pace multiplier table and streak bonus cap from
  tech-spec.md §2.2–2.3; `XCTest` unit tests that load
  `shared/point-formula.fixtures.json` (tech-spec.md §2.2b) and assert
  `calculatePoints` matches every fixture row's `expected_points`, plus
  tests covering each pace bracket edge and the streak cap directly.
- Yang TIDAK dikerjakan: anti-cheat logic (that's server-side only, Fase
  2) — this function assumes clean input, it does not validate GPS data.

**Note on gps_route (tech-spec.md §2.1):** this function takes already-
derived `distanceKm`/`avgPaceSecPerKm`, not raw GPS points — it has no
dependency on the shape of `gps_route` and needs no changes when that
payload's per-point structure changes (it did, see database-api-spec.md
§1/§2.2). The raw per-point data (`{lat, lng, timestamp, elevation}`) is
only consumed by T0.8 (client capture) and by the server's anti-cheat
checks (T2.7–T2.10) — `calculatePoints` and its server counterpart (T2.6)
stay decoupled from it by design, which is exactly what keeps them
identical.

**Depends on:** T0.1, T0.2 (needs the Xcode project and `ios/LajuTests`
target to exist — this task creates real Swift source and XCTest content,
unlike its pre-pivot TS-file predecessor which only needed repo scaffolding)

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.2–2.3, §2.2b

**This task owns authoring `shared/point-formula.fixtures.json`'s
content** (T0.1 only creates it as an empty `[]` placeholder) — since the
fixture is now the *only* mechanism preventing client/server point
divergence post-pivot (no more literal shared source file), an empty or
sparse fixture would make the parity guarantee vacuous.

**Definition of Done:**
- [x] Function signature and constants (`streakBonusPerDay`, pace
      brackets) match tech-spec.md §2.3 exactly — `PointFormula.swift`:
      `streakBonusPerDay=2`, brackets `<180→0.5, [180,240)→1.2,
      [240,420)→1.0, [420,600)→0.9, ≥600→0.7`, verified by direct
      comparison against tech-spec.md's table
- [x] Unit tests cover: each pace bracket boundary, streak cap at 7 days,
      zero-distance edge case — `PointFormulaTests.swift`, all passing on
      simulator (iPhone 17, iOS 26.3)
- [x] `shared/point-formula.fixtures.json` populated with ≥1 vector per
      pace bracket (covering both sides of each half-open boundary),
      streak days at 0/1/7/8, and a zero-distance case — 13 rows, no
      longer the empty `[]` placeholder from T0.1
- [x] `XCTest` fixture-parity test passes against
      `shared/point-formula.fixtures.json` (tech-spec.md §2.2b), and fails
      if the fixture file is empty (row-count assertion) — `testFixtureParity`,
      passing; all 13 fixture rows verified against `calculatePoints`
      output (accuracy 0.0001)

**Formula revised 2026-09-13 — real grinding exploit found on-device, not
just a code bug:** `calculatePoints` gained `minDistanceKmForPoints`
(0.1km) gating TOTAL points (base **and** streak bonus) to 0 below it —
previously the additive streak bonus survived `distanceKm=0` entirely,
confirmed on-device as 6.0/8.0 points from two `distanceMeters=0` runs
(streak_days 3/4). tech-spec.md §2.2 updated first, then
`PointFormula.swift`, `shared/point-formula.fixtures.json` (+3 rows), and
`PointFormulaTests.swift` (+3 tests, including the exact exploit
scenario). **Re-verified, not silently left "done"**: all DoD items above
still hold against the revised spec — 32/32 tests passing, including the
new regression coverage. This task's own scope (function signature,
brackets, fixture-parity mechanism) is unchanged; only the formula's
behavior at the boundary this task never originally tested (distance
below a floor) changed.

---

### T1.2 — Post-run summary screen wired to point-formula (offline estimate)

**Objective:** Deliver the "instant reward" moment — the core hypothesis
being tested per product-spec.md §1.

**Scope:**
- Yang dikerjakan: on run stop, call `calculatePoints` from
  `ios/Laju/PointFormula`, display distance/duration/pace/estimated
  points on a SwiftUI summary screen (View + ViewModel, MVVM), persist
  `estimatedPoints` to the `Run` entity.
- Yang TIDAK dikerjakan: level display (T1.3), streak input wiring beyond
  passing a placeholder value (T1.4 wires the real streak count in).

**Depends on:** T1.1, T0.8

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.3 AC1

**Definition of Done:**
- [x] Summary screen appears within 2 seconds of stopping a run
      (product-spec AC 4.3.1) — `completedRunSummary` is set synchronously
      inside `stop()` (no async delay in the chain at all), and
      `RunTrackingView` presents it via `.sheet(item:)`; verified the
      state transition is immediate via `testStopWithNoMovementProducesZeroPointSummary`
      (`RunViewModelTests.swift`). **Visually confirmed on physical device
      (iPhone 13, 2026-09-12):** Run Summary sheet appeared instantly on
      Stop.
- [x] Displayed points match `calculatePoints` output for the recorded
      distance/pace — `testStopWithMovementComputesMatchingPoints`
      (simulated GPS movement) and `testStopWithNoMovementProducesZeroPointSummary`
      (zero-distance) both assert `completedRunSummary.estimatedPoints`
      equals an independently-computed `PointFormula.calculatePoints`
      call using the same recorded distance/duration
- [x] `estimatedPoints` persisted on the `Run` entity — both tests above
      also fetch the `Run` row back from Core Data and assert
      `run.estimatedPoints` matches the summary

**Km display decision (tech-spec.md §2.1c) applied here**: `RunSummaryView`
is the first real user-facing screen showing distance, so it uses
`DistanceFormatter` (km, 2dp <10km / 1dp ≥10km) — `RunTrackingView`'s debug
meter readout is intentionally left as-is (documented exception, §2.1c).

---

### T1.2b — Pause/resume run tracking

**Objective:** Cover product-spec.md AC 4.2.3 ("User bisa start/**pause**/
stop run dengan jelas dari UI") — a Must-have acceptance criterion with
zero task coverage through 3 audit rounds. Pause must be handled
correctly at the GPS/state level since it directly affects what T1.2's
summary screen displays and, later, what T2.9 (Fase 2 teleport check)
must not misread as an anomaly.

**Scope:**
- Yang dikerjakan: Pause/Resume control added to T0.8's start/stop UI.
  **State preserved across pause** (none of it resets): elapsed
  `durationSeconds` (timer stops accumulating while paused, resumes
  from the same value), `distanceMeters` (stops accumulating while
  paused), and the displayed `estimatedPoints` from T1.2 (freezes at
  its last computed value while paused, recalculates normally after
  resume). **`CLLocationManager` behavior on pause: updates are actually
  stopped**, not "keep receiving updates but ignore the points" —
  `stopUpdatingLocation()` is called for the duration and
  `startUpdatingLocation()` resumes it. This is a deliberate choice, not
  just a battery optimization: it means the gap between the last
  pre-pause point and the first post-resume point is a real time gap with
  no fabricated intermediate points, so it cannot produce a spurious
  "large distance in a short interval" pattern for T2.9's teleport check
  to misinterpret later — there is nothing to misinterpret, since no
  points span the pause at all.
- Yang TIDAK dikerjakan: any anti-cheat-side awareness of pause gaps —
  the design above means the server needs no special-case logic for
  pauses; this task only guarantees the client-side data produced across
  a pause is structurally clean.

**Depends on:** T0.8, T1.2

**Reference:** [product-spec.md](../../01-product/product-spec.md) AC 4.2.3

**Definition of Done:**
- [x] User can pause and resume a run any number of times from the UI,
      visually distinct from stop — `RunTrackingView`: Pause/Resume is
      `.bordered` style, Stop is `.borderedProminent` with `.tint(.red)`;
      `pause()`/`resume()` guard on `isRunning`/`isPaused` so calling
      either repeatedly is a no-op, not an error — any number of
      pause/resume cycles is safe. **Visually confirmed on physical
      device (iPhone 13, 2026-09-12):** Start→Pause→Resume→Stop cycle
      run by the user, Pause/Resume/Stop all behaved as expected.

**Second real bug found during this device re-verification pass
(2026-09-12):** device stationary indoors, Start→Pause(~10s)→Resume(~5s)
→Stop recorded 35m of distance and an absurd pace, even though
`stationaryAnchor` (T0.9) was untouched by pause/resume (confirmed by
code inspection — ruled out a location-manager-restart hypothesis first).
Console log from the device pinned the actual cause: the run's first
accepted GPS fix had `horizontalAccuracy=15.11m` and became the anchor
unconditionally; 12s later a much more accurate fix (`3.20m`) landed
~35.0m away — beyond both the 20m anchor radius and the per-point jitter
floor, so it read as real movement even though the phone never moved. The
first-fix's own accuracy was never checked before trusting it as the
anchor. **Fix:** `RunViewModel.swift` — a fix can only establish/move
`stationaryAnchor` if `horizontalAccuracy ≤ 10m`
(`anchorAccuracyThresholdMeters`); a poorer fix is still recorded to
`gpsRoute` but never becomes the reference point. Regression test added:
`testPoorAccuracyFirstFixDoesNotSeedFalseAnchorDrift`
(`RunViewModelTests.swift`), using the exact coordinates/accuracy from the
incident log. Retested the identical device scenario post-fix:
`distanceMeters` stayed 0m end to end, confirmed both in the UI and by
pulling the on-device Core Data store (`devicectl device copy from` →
`Laju.sqlite`) — the previous buggy run (34.80m, matching the original
report) remains in the store as historical evidence. Full writeup:
tech-spec.md §2.1b.
- [x] `durationSeconds` and `distanceMeters` correctly exclude paused
      time — verified against a manually timed pause/resume cycle —
      `testPauseExcludesElapsedTimeFromDuration`: real 0.3s/0.5s/0.3s
      active/paused/active sleep cycle, asserts final `durationSeconds`
      ≈0.6s (the active sum), not ≈1.1s (the full wall-clock span).
      `distanceMeters` freezing is structural, not timing-based: no new
      location events are ever processed while paused (see next item),
      so there's nothing to accumulate.
- [x] No new Core Data `gpsRoute` points are recorded during a paused
      interval (verified directly against the local persistent store) —
      `testNoPointsRecordedWhilePaused`: 1 point before pause, 2 more
      injected during the paused interval are rejected by `handle(_:)`'s
      own `!isPaused` guard (not merely absent because
      `CLLocationManager` was told to stop — the guard is a second,
      independent safeguard against an in-flight update racing a pause),
      confirmed both via `pointCount` and by decoding the persisted
      `gpsRoute` back from Core Data (1 point, not 3).
- [x] `estimatedPoints` (T1.2) does not change while paused and resumes
      updating correctly after resume —
      `testCurrentEstimatedPointsFreezesWhilePausedThenResumesUpdating`:
      `currentEstimatedPoints` (T1.2b's new live estimate, distinct from
      T1.2's final `estimatedPoints` computed once at Stop) unchanged
      across a pause despite an attempted update, then changes after a
      post-resume point.

---

### T1.3 — Local level progression from cumulative points

**Objective:** Give the user a longer-horizon goal beyond a single run.

**Scope:**
- Yang dikerjakan: `levelThresholds` static config (level number, points
  required, title) in `ios/Laju/PointFormula`; function deriving
  `currentLevel` and `pointsToNextLevel` from a user's local cumulative
  points (sum of `estimatedPoints` across synced+local runs). Values must
  match database-api-spec.md §1's table exactly — that table is the single
  reference both this Swift config and the backend's T2.15 config copy
  from (it is small/static enough that a literal fixture file is
  unnecessary; a direct hardcoded-values-match-the-doc unit test is
  sufficient parity).
- Yang TIDAK dikerjakan: any server-side level storage (Fase 2); level-up
  notification UI polish beyond a basic visual indicator.

**Depends on:** T1.2

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.4,
[database-api-spec.md](../../02-architecture/database-api-spec.md) §1 (Level note)

**Definition of Done:**
- [x] Level correctly derived from cumulative local points against the
      threshold table — `LevelProgression.currentLevel`/`pointsToNextLevel`,
      `testCurrentLevelBoundaries` checks every boundary from 0 to 12000,
      `testTopLevelHasNoCapBeyondLevelEight` checks the uncapped-top-level
      behavior (database-api-spec.md §1's own stated rule)
- [x] `levelThresholds` values match database-api-spec.md §1's table
      exactly, row for row — verified by a test, not just visually —
      `testLevelThresholdsMatchDatabaseApiSpecExactly`, direct
      `Equatable` comparison against the 8-row table
- [x] A basic visual/notification appears when a run causes a level-up
      (product-spec AC 4.4.2) — `RunViewModel.stop()` compares cumulative
      points before/after this run via `PersistenceController
      .totalEstimatedPoints`, sets `RunSummary.leveledUpTo` when the
      level increased; `RunSummaryView` shows a "Level Up!" banner when
      set. Verified via `testStopDetectsLevelUp` (95→100+ crosses level 2)
      and `testStopDoesNotReportLevelUpWhenStillBelowThreshold` (stays
      nil when not crossed). **Visually confirmed on physical device
      (iPhone 13, 2026-09-12).**

**Cross-cutting fix found while adding this task's tests**: SwiftFormat's
default trailing-comma style conflicted with SwiftLint's `trailing_comma`
rule on multi-line array literals — `.swiftformat` now sets
`--commas inline` explicitly (repo-coding-rules.md §3 updated to match).

---

### T1.4 — Local streak tracking feeding streak_bonus

**Objective:** Wire the streak variable that T1.1's formula already
supports but T1.2 stubbed out.

**Scope:**
- Yang dikerjakan: a named `StreakTracker` type computing `streakDays`
  from consecutive-day run history in local Core Data, passing the real
  value into `calculatePoints` on the summary screen; exposes a
  `hasRunToday`-equivalent query (or an already-computed today's-streak
  value the caller can compare against zero) — T1.16's streak-reminder
  scheduling (tech-spec.md §5.2) depends on this exact query existing,
  not a bespoke one it has to build itself (2026-09-13, Round 7 finding
  N7-P12).
- Yang TIDAK dikerjakan: any streak-specific UI beyond what product-spec
  §3 calls "streak indicator" (Should-have, can be minimal — a number is
  enough for this task).

**Note (2026-09-13, grinding-exploit fix):** `StreakTracker.currentStreakDays`
itself is unchanged — still a pure function, still 5/5 tests passing. What
changed is how `RunViewModel` calls it: `PersistenceController.runStartDates`
now filters to qualifying-distance runs only
(`PointFormula.minDistanceKmForPoints`), and `RunViewModel` computes the
prior streak `asOf` yesterday rather than today, adding +1 only if today's
own run clears the distance floor (see `RunViewModel.effectiveStreakDays`).
This task's own DoD (streak resets on a missed day, streak bonus matches
`calculatePoints`) still holds — re-verified via
`RunViewModelStreakTests.swift`'s 3 tests, still not yet marked `[x]`
pending the device re-verification already queued from before this fix.

**Depends on:** T1.2

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.1, §2.2

**Definition of Done:**
- [x] Streak count correctly resets when a day is missed (verified with
      manually seeded run timestamps) — `StreakTrackerTests.swift`
      (5 tests: consecutive count, reset at first missed day, same-day
      runs count once, no-run-today breaks streak, streak-of-one)
- [x] Streak bonus in the displayed point estimate matches
      `calculatePoints` given the computed streak —
      `RunViewModelStreakTests.swift` (3 tests) + confirmed on physical
      device across this session's own runs (RunSummaryView's "Streak"
      row, e.g. the 24km run 2026-09-13: "Streak: 1 day" alongside the
      correct final points)
- [x] `StreakTracker` exposes a query T1.16 can call directly to check
      "has today already had a run" without re-deriving streak logic —
      **added 2026-09-14**: `StreakTracker.hasRun(on:runDates:calendar:)`,
      same `runDates` input as `currentStreakDays` (3 new tests)

---

### T1.5 — Local run history screen

**Objective:** Let the user see past runs. **Promoted from Should-have to
Must-have 2026-09-13 (Round 7 finding N7-4)** — T1.9 (static route map)
depends on this screen existing to render on; a Must-have AC (product-spec
§4.9 AC2) cannot correctly depend on a cuttable Should-have, so this task
is no longer optional under time pressure. Also still doubles as a
debugging/QA surface for this phase.

**Scope:**
- Yang dikerjakan: SwiftUI list screen (`@FetchRequest` or
  `NSFetchedResultsController`-backed ViewModel) reading all local `Run`
  entities, showing date, distance, pace, estimated points.
- Yang TIDAK dikerjakan: filtering/sorting beyond reverse-chronological,
  any server sync status indicator (no server yet).

**Depends on:** T1.2

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.18

**Definition of Done:**
- [x] All local runs appear in the list, most recent first — `@FetchRequest`
      sorted by `startedAt` descending (`RunHistoryView.swift`); verified
      on physical device (2026-09-13)
- [x] Displayed values match what's stored in Core Data for each run —
      date/distance/pace/points read directly from the `Run` entity, no
      transformation beyond the already-established `DistanceFormatter`/
      `PaceFormatter`; verified on physical device against real run data,
      empty state confirmed distinct from a blank/broken screen

---

### T1.6 — Local profile/progress screen (offline)

**Objective:** Give the user a single place to see overall progress, not
just per-run.

**Scope:**
- Yang dikerjakan: screen showing total local points, current level,
  progress bar to next level (reuses T1.3's derivation function).
- Yang TIDAK dikerjakan: region/profile fields (that's account setup,
  Fase 2 territory since it requires a server identity) — this screen is
  progress-only.

**Depends on:** T1.3

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.4 AC3

**Definition of Done:**
- [x] Progress bar and level shown match T1.3's derivation for the
      current local run history — **built 2026-09-14** as part of the
      design-system pass (`ProfileView.swift`): `levelSection` calls
      `LevelProgression.currentLevel`/`pointsToNextLevel` directly on
      `totalPoints` (sum of all fetched `Run.estimatedPoints`), same
      derivation T1.3 already tests
- [x] Screen updates immediately after a new run is completed (no app
      restart needed) — `@FetchRequest` on `Run` (same live-updating
      mechanism `RunHistoryView`/T1.5 already relies on and was
      device-verified for), so `totalPoints`/streak/recent-runs all
      recompute the instant a new `Run` is saved, no restart

**Note:** this task's screen was built ahead of being explicitly picked
up, during the 2026-09-14 design-system overhaul (Langkah 6 required a
"Profile/Level screen" as part of that pass) — reconciled here rather
than building a duplicate. `swiftlint --strict` clean, full 60-test suite
passing, installed and running on physical device as of that session.

---

### T1.8 — Live map during tracking (MapKit)

**Objective:** Close product-spec.md §4.8 — added 2026-09-12 alongside 8
other gap items found by sweeping for implicit requirements (App Store
standards, competitor baseline, persona consistency) the original
breakdown missed. This item and T1.9 can be worked in parallel — both
only consume `gpsRoute` data T0.8 already captures, they don't share
implementation.

**Scope:**
- Yang dikerjakan: `Map`/`MKMapView` on `RunTrackingView` showing current
  user position and a live-updating `MKPolyline` built from `gpsRoute`
  points already flowing through `RunViewModel.handle(_:)` (T0.8/T1.2b) —
  see tech-spec.md §5.1 for the exact data flow (no new location
  requests, no new Core Data fields).
- Yang TIDAK dikerjakan: static map rendering for completed runs (T1.9);
  any routing/geocoding/search MapKit features beyond position + polyline
  display.

**Depends on:** T0.8, T1.2b

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.8,
[tech-spec.md](../../02-architecture/tech-spec.md) §5.1

**Definition of Done:**
- [x] Map is visible on the tracking screen during an active run, showing
      the user's current position, via a custom annotation driven by
      `RunViewModel`'s published location state — NOT
      `MKMapView.showsUserLocation`/`UserAnnotation` (tech-spec.md §5.1,
      2026-09-13 Round 7 finding B7-8: those start MapKit's own internal
      location subscription, invisible at any `CLLocationManager`
      call site). Verified on physical device (2026-09-13): map appeared,
      custom pin tracked the user's real position (confirmed against the
      on-device Core Data store — 2 accepted GPS points matching the
      console log exactly)
- [x] Polyline reflects the route recorded so far, updating as new points
      arrive, with no separate/duplicate location subscription from the
      existing `LocationTrackingService` — confirmed both visually
      on-device and via `RunViewModelMapTests.swift` (4 tests)
- [x] No new GPS polling introduced — verified by inspecting
      `CLLocationManager` call sites AND by confirming the forbidden
      MapKit APIs above are absent (grep-able): only `LocationTrackingService`
      instantiates `CLLocationManager()`; `showsUserLocation` appears only
      set to `false`, `UserAnnotation` never used
- [ ] Battery draw with the map on screen during an active run
      re-measured against T0.9's 3%/hour baseline (tech-spec.md §4) —
      **DEFERRED 2026-09-13** (same pattern as T0.9's own battery item
      historically): needs a real ~15-20min foreground, screen-on,
      actually-moving physical test, deliberately batched into one full
      testing session later rather than run in isolation now. Tracked in
      [deferred-manual-tests.md](../../04-quality-security/deferred-manual-tests.md). Not a
      blocker — T1.8 proceeds as partial, next task starts now. *(A
      duplicate copy of this same DoD item sat directly below this one
      until 2026-09-17; removed — it was one item listed twice, which made
      T1.8 read as having 2 outstanding tests instead of 1.)*

---

### T1.9 — Static route map (Run Summary & History)

**Objective:** Close product-spec.md §4.9 — renders already-captured
`gpsRoute`, no new data collection. Can be worked in parallel with T1.8.

**Scope:**
- Yang dikerjakan: `MKPolyline` rendered read-only from a completed run's
  stored `gpsRoute` (decoded the same way `RunViewModel`'s flush/decode
  path already does), shown on `RunSummaryView` (T1.2) and on each row in
  Run History (T1.5).
- Yang TIDAK dikerjakan: live location, any user interaction with the map
  beyond viewing (zoom/pan is fine via MapKit defaults, no custom
  controls needed for v1). Run History rows use cached
  `MKMapSnapshotter` thumbnails (decoded off the main thread), not a live
  `MKMapView` per row (2026-09-13, Round 7 finding N7-9 — a live map view
  per list row is a known scroll-performance trap); a live `MKMapView` is
  only for the Run Summary/detail view.

**Depends on:** T1.2, T1.5

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.9,
[tech-spec.md](../../02-architecture/tech-spec.md) §5.1

**Definition of Done:**
- [x] Run Summary shows a static route map matching the just-completed
      run's `gpsRoute` — verified on physical device (2026-09-13) and
      against the on-device Core Data store: run pk=80 had 4 stored GPS
      points, matching the console log's 4 accepted fixes and the
      rendered polyline
- [x] Run History shows the same rendering per past run, from stored data
      only (no re-tracking) — `MKMapSnapshotter`-based thumbnail per row
      (`RunRouteThumbnailView`), verified on-device
- [x] A run with zero/one GPS points shows a clear empty state, not a
      blank or broken map view — confirmed on-device against real prior
      runs with only 1 stored point (pk=78/79)

---

### T1.10 — Splits per kilometer

**Objective:** Close product-spec.md §4.10.

**Scope:**
- Yang dikerjakan: pure function slicing a completed run's `gpsRoute` into
  per-km segments (cumulative distance crossing each 1km boundary),
  computing pace per segment; displayed as a list on `RunSummaryView`.
  **Must replicate `RunViewModel`'s `stationaryAnchor` acceptance logic
  when deriving distance from `gpsRoute`** (tech-spec.md §2.1b, 2026-09-13
  Round 7 finding B7-1) — `gpsRoute` contains every accepted-but-not
  necessarily distance-counted point (drift points are recorded raw but
  excluded from `distanceMeters`), so naive point-to-point summation would
  NOT equal `distanceMeters`. A split spanning a paused interval (T1.2b)
  has a real time gap with no intermediate points — exclude that gap from
  the split's pace, don't let it inflate it (2026-09-13, Round 7 finding
  N7-P4).
- Yang TIDAK dikerjakan: any UI beyond a simple list (charting/graphing is
  not required for v1).

**Depends on:** T1.2, T1.2b

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.10,
[tech-spec.md](../../02-architecture/tech-spec.md) §2.1b

**Definition of Done:**
- [x] Splits list shows one row per completed km plus a final partial
      split (clearly marked as partial, not rounded up/hidden) — verified
      2026-09-13 on physical device, real ~24km run (pk=81, tech-spec.md
      §2.1b): `RunSummaryView` showed "Km 1: 2:13/km" through "Km 22
      (partial): 7:39/km", 22 rows total, trailing row correctly marked
      partial
- [x] Sum of all split distances equals the run's total recorded distance
      (verified by test, not just visual inspection) — achievable only by
      replicating the anchor logic, not raw point-to-point summation —
      `RunViewModelSplitsTests.testSplitDistancesSumExactlyToTotalDistance`
      (guaranteed by construction: `SplitTracker` derives splits from the
      same live `distanceMeters` accumulation, not a separate re-derivation
      from `gpsRoute`)
- [x] A split spanning a paused interval excludes the paused time from
      that split's pace (verified with a seeded pause-gap fixture) —
      `RunViewModelSplitsTests.testSplitSpanningAPauseExcludesThePausedTimeFromItsDuration`

---

### T1.11 — Auto-pause (user-facing)

**Objective:** Close product-spec.md §4.11 — REUSES the existing
`stationaryAnchor`/`stationaryRadiusMeters` drift guard (T0.9/T1.2b,
tech-spec.md §2.1b) as the detection basis, turned into an explicit
user-facing Pause trigger instead of a silent distance-suppression
mechanism. Not built from scratch.

**Scope:**
- Yang dikerjakan: **a periodic timer** (not a callback reactive to GPS
  fix arrival — 2026-09-13, Round 7 finding B7-3: the anchor is only
  evaluated when a fix arrives, and tech-spec.md §2.1b's own T0.9 retest
  shows a stationary device receives almost no fixes at all — a
  fix-reactive trigger would never fire on the exact condition it must
  detect) checking elapsed time since `stationaryAnchor` last moved
  (confirmed real movement); past a configured threshold, `RunViewModel`
  transitions into the same `isPaused` state T1.2b's manual Pause already
  uses — with a distinct UI label ("Auto-paused") so the user can tell it
  apart from a manual pause; user can Resume manually same as after a
  manual pause (auto-resume is explicitly out of v1 scope — GPS is fully
  stopped during any pause, T1.2b, so there's no signal to auto-detect
  resumed movement). This is also the first task to genuinely exercise
  the anchor's 20m radius-check in practice — T0.9's own retest never saw
  a second point land inside it.
- Yang TIDAK dikerjakan: any new drift-detection algorithm — the anchor's
  drift-vs-real-movement judgment is unchanged; this task only adds a
  time-based observer of when the anchor last moved, plus the state
  transition, on top of logic that already exists.

**Depends on:** T1.2b

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.11,
[tech-spec.md](../../02-architecture/tech-spec.md) §2.1b

**Threshold: 60 seconds** since the last confirmed real movement (chosen 2026-09-13 — long enough to survive a
brief stop, e.g. checking a phone or a crosswalk, without misfiring; short enough to still catch a genuine stop,
e.g. a red light). `AutoPauseThreshold.seconds`; injectable per-`RunViewModel` for tests.

**Definition of Done:**
- [x] Sustained no-movement past the configured threshold during an
      active run transitions to Pause automatically, without user input
      — verified with the device genuinely stationary (near-zero GPS
      fixes), not just by manually invoking the check. Device-verified
      with full console logging (2026-09-13): first auto-pause fired
      ~60s after the anchor was established; after Resume, the watchdog
      correctly reset its clock and the SECOND auto-pause fired at
      elapsed=60.57s — confirming the reset-on-resume logic, not just
      the initial trigger (an earlier manual test without logging
      appeared to show an early ~29s re-trigger; the logged
      reproduction showed this was not reproducible and the mechanism
      fires exactly at the 60s mark).
- [x] UI visibly distinguishes auto-pause from manual pause — orange
      "Auto-paused — kamu berhenti bergerak" banner (`RunTrackingView`),
      confirmed visible on-device by the user, distinct from the
      Pause/Resume button which always just reads "Resume".
- [x] Resume from an auto-pause behaves identically to resume from a
      manual pause (T1.2b's existing DoD/tests) — auto-resume is not
      required and not attempted. Verified via
      `RunViewModelAutoPauseTests` and on-device (Resume from an
      auto-pause continued tracking normally).
- [x] Auto-paused time is excluded from `durationSeconds`/pace exactly
      like manual pause (product-spec §4.11 AC4) —
      `RunViewModelAutoPauseTests.testAutoPausedTimeIsExcludedFromDuration`,
      cross-checked against the on-device persisted `durationSeconds`
      (froze at the exact auto-pause moment both times).

---

### T1.12 — Elevation gain/loss

**Objective:** Close product-spec.md §4.12 — `elevation` per `gpsRoute`
point already captured since T0.8, this task only computes and displays
it.

**Scope:**
- Yang dikerjakan: pure function computing cumulative elevation gain and
  loss from a completed run's `gpsRoute`, with noise smoothing (raw
  per-point altitude deltas are not summed unfiltered — GPS altitude is
  notoriously noisy); displayed on `RunSummaryView`. Consider whether
  drift/anchor-suppressed points (tech-spec.md §2.1b, 2026-09-13 Round 7
  finding B7-1) should be excluded the same way splits (T1.10) exclude
  them from distance — a stationary period's altitude jitter is exactly
  the kind of noise this task's smoothing must already tolerate, so this
  may already be covered by the noise-smoothing requirement itself rather
  than needing separate point-filtering.
- Yang TIDAK dikerjakan: any elevation chart/profile visualization beyond
  the two summary numbers.

**Depends on:** T1.2

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.12

**Definition of Done:**
- [x] Run Summary shows total elevation gain and loss for the completed
      run — `ElevationTracker.compute(points:)` (new, 2026-09-14), called
      once in `RunViewModel.stop()` against the just-flushed `gpsRoute`
      and in `RunRecovery.finalize` (crash-recovered runs get the same
      treatment); displayed as two new rows ("Elevation Gain"/"Elevation
      Loss") in `RunSummaryView`'s stat grid via new `ElevationFormatter`.
      **Build/install/launch confirmed clean on physical device
      (2026-09-14, device reconnected later in session)** — visually
      reading the actual gain/loss numbers on a completed run's summary
      screen still needs a real run + eyes on the device, not something
      confirmable from this session's tooling alone.
- [x] A flat/noisy-but-flat route (small random altitude jitter, no real
      elevation change) does not produce a materially inflated gain/loss
      number — verified with a synthetic noisy-flat fixture, not just a
      real hilly route — `ElevationTrackerTests.testFlatNoisyRouteProducesNegligibleGainAndLoss`
      (10-point jitter fixture, all deltas under the 3m noise floor,
      asserts gain=loss=0); `testRealClimbSurvivesSmallJitterOnTop`
      confirms the same floor doesn't also eat a genuine climb once it
      clears 3m

**Noise smoothing approach:** `ElevationTracker.noiseFloorMeters = 3` —
mirrors `RunViewModel`'s own `stationaryAnchor` pattern (a reference
point that only moves once a change clears a floor); drift/anchor-
suppressed points (tech-spec.md §2.1b) are NOT separately excluded —
the noise floor already absorbs a stationary period's altitude jitter,
confirmed by `ElevationTrackerTests` rather than assumed.

**Refactor alongside this task:** extracted `RoutePointBuffer` (new,
`ios/Laju/ViewModels/RoutePointBuffer.swift`) out of `RunViewModel` —
this task's addition pushed `RunViewModel`'s `type_body_length` to 253
lines (limit 250); the pending-GPS-points buffer/flush logic was already
a separable concern (same extraction pattern as `SplitTracker`/
`AutoPauseWatchdog`), moved out with no behavior change, re-verified by
the full test suite passing unchanged.

---

### T1.13 — Audio cues

**Objective:** Close product-spec.md §4.13.

**Scope:**
- Yang dikerjakan: `AVSpeechSynthesizer` announces distance + current
  pace each time a new km boundary is crossed during an active run (state
  tracked via a new `lastAnnouncedKm`, mirroring the existing
  `lastLocation`/`stationaryAnchor` pattern in `RunViewModel` — see
  tech-spec.md §5.3); user-facing toggle (persisted via `UserDefaults`) to
  disable audio cues entirely. **`UIBackgroundModes` in `Info.plist` gains
  `audio`** alongside the existing `location` (tech-spec.md §5.3,
  2026-09-13 Round 7 finding B7-5) — without it, announcements stop the
  moment the screen locks/app backgrounds, which is the exact condition
  this feature exists for. `AVAudioSession` category is `.playback` +
  `.duckOthers`, not `.ambient` (tech-spec.md §5.3 — `.ambient` cannot
  play in background at all).
- Yang TIDAK dikerjakan: time-interval-based cues (distance-based only for
  v1).

**Depends on:** T1.2, T1.2b

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.13,
[tech-spec.md](../../02-architecture/tech-spec.md) §5.3,
[pre-launch-checklist.md](../../04-quality-security/pre-launch-checklist.md) §10

**Design deviation from Scope (2026-09-14):** no separate `lastAnnouncedKm`
was built. `SplitTracker` (T1.10) already detects a km boundary crossing
exactly once, immune to GPS jitter, via `splits.count` only growing past
1000m accumulated since the last boundary — `RunViewModel
.announceKmBoundaryIfCrossed` reuses that same detection (compares
`splitTracker.splits.count` before/after `recordDistanceUpdate`) instead
of re-implementing an equivalent second tracker. Pace announced is that
completed split's own `avgPaceSecPerKm` (that km's pace), not a lifetime
average — read as the more useful "current pace" figure at a boundary.

**Definition of Done:**
- [x] An audio announcement fires exactly once per km boundary crossed
      during an active run, containing both the new km figure AND current
      pace (product-spec §4.13 AC1 — content, not just frequency) —
      `AudioCueService.announcementText(kmNumber:paceSecPerKm:)`; wired via
      `RunViewModel.announceKmBoundaryIfCrossed`, called from `handle(_:)`
      on every accepted movement. `RunViewModelAudioCueTests
      .testAnnouncesExactlyOnceWhenAKmBoundaryIsCrossed` +
      `testAnnouncesAgainOnASecondBoundaryCrossing` (spy-based, no real
      TTS needed)
- [x] Toggling the setting off suppresses all future announcements for
      that run and subsequent runs until re-enabled — `AudioCueService
      .isEnabled` persists globally via `UserDefaults`
      (`enabledDefaultsKey`), checked at the top of every `announce(_:)`
      call, not per-`RunViewModel` instance state — a toggle flip
      survives across runs and app relaunches by construction.
      User-facing toggle added to `ProfileView` (no dedicated Settings
      screen exists yet — nearest existing home). Tested:
      `AudioCueServiceTests.testDisablingSuppressesFutureAnnouncements`
- [x] GPS jitter around a km boundary (multiple updates near the same
      threshold) does not cause a duplicate announcement for the same km
      — inherited directly from `SplitTracker`'s own jitter-immune
      boundary detection (T1.10), not a new dedupe mechanism. Verified:
      `RunViewModelAudioCueTests
      .testDoesNotAnnounceAgainForFurtherMovementWithinTheSameKm`
- [ ] Verified on a physical device with the screen locked/app
      backgrounded — same bar T0.9 set for background location — not just
      a foreground simulator run. **PARTIALLY DONE 2026-09-14**: device
      reconnected later in the session — build/install/launch on
      `Ripo Gagah` (iPhone 13) confirmed clean (console showed a normal
      GPS fix cycle, no crash). Still not done: the specific screen-locked
      background-audio scenario itself (the entire point of the
      `UIBackgroundModes: audio` change) needs a hands-on test — start a
      run, lock the screen, walk ≥1km, confirm the announcement is heard
      — which needs a person physically holding the device, not something
      drivable from this session (no simulator-style screen/touch control
      exists here for a physical device, only install/launch/log-pull via
      `devicectl`).

---

### T1.14 — Crash/interrupt recovery flow

**Objective:** Close product-spec.md §4.14.

**Scope:**
- Yang dikerjakan: on app launch, check for a local `Run` row with no
  `endedAt` (T0.6 schema) left over from a previous session (force-quit
  or crash mid-run); present an explicit resume-or-discard choice to the
  user. **Must also add incremental persistence of `durationSeconds`**
  (2026-09-13, Round 7 finding B7-2/B7-P1) — T0.8's Scope currently only
  describes `durationSeconds` as finalized at Stop, and the shipped
  `RunViewModel` only writes it in `pause()`/`stop()`; a crash mid-active-
  segment (never paused) leaves the persisted row at `durationSeconds=0`,
  making "resume from previously-saved duration" impossible without this.
  Reuses the same incremental-flush trigger T0.8/T1.2 already has for
  `gpsRoute`/`distanceMeters`, not a new mechanism. A resume offer should
  also have a staleness cutoff (a run abandoned days ago is more likely
  worth discarding by default than silently offering to resume it
  indefinitely) — exact cutoff decided at implementation time.
  **Decision (2026-09-13, at implementation): staleness cutoff = 24h;
  "discard" replaced by "Save as finished"** — see DoD below for why.
- Yang TIDAK dikerjakan: any change to the normal (non-crash) start/stop
  UX itself (T1.2/T1.2b) — only the incremental duration-persistence
  addition above and the launch-time recovery check are in scope.

**Depends on:** T0.6, T0.8, T1.2

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.14

**Definition of Done:**
- [x] An unfinished run (no `endedAt`) from a previous session is detected
      on next app launch and surfaced to the user with resume/discard
      options — **decision (2026-09-13, in-conversation product
      refinement): "Discard" replaced by "Save as finished"** (closes the
      run at its last persisted state instead of throwing the data away —
      see `RunRecovery.finalize`). Multiple unfinished runs: only the
      most recent is prompted, older ones auto-finalize (superseded by a
      later session). A run older than 24h (`RunRecovery.staleAfter`) is
      too stale to offer Resume and auto-finalizes too. Verified on
      physical device: force-kill mid-run → reopen → prompt shows
      correct start time/distance → both Resume and Save-as-finished
      paths confirmed working by the user.
- [x] ~~Discard removes...~~ superseded by the decision above — see that
      line. `RunRecoveryTests` covers the "Save as finished" path
      (`endedAt` set to the last GPS fix's timestamp, not "now"; correct
      final points computed).
- [x] Resume continues tracking from the previously-saved
      distance/duration/gpsRoute state, not from zero — verified by
      `RunViewModelResumeTests` (crash mid-active-segment, never paused)
      AND on physical device (multiple force-kill/resume cycles). The
      anchor/last-known-position also carries over unchanged (treated
      like a long `pause()`, per 2026-09-13 scope simplification), not
      reset — new fixes post-resume flow through the same anchor/speed
      pipeline as any other point, no special-case logic.
- [x] `durationSeconds` incremental persistence (B7-2/B7-P1) — the
      periodic-flush trigger (`RunViewModel.periodicFlush()`) always
      persists `durationSeconds`, not just `gpsRoute`/`distanceMeters`.
      **On-device finding (2026-09-13):** the original 30s interval was
      technically correct (mechanism verified working via console+DB,
      `durationSeconds=30.008` saved exactly at the 30s mark) but too
      wide for comfortable resume granularity — two user trials each hit
      a kill inside that window and appeared to "lose" progress that was
      simply never due to flush yet. Tightened to **5s** — worst-case
      loss on any kill is now ≤5s. A kill within one interval of a fresh
      Resume still loses that segment (the resumed session's own timer
      restarts from 0) — a real, disclosed limitation, not solved by
      shrinking the interval further (diminishing returns vs. disk-write
      frequency). Re-verified on device after the change: confirmed
      working by the user.

---

### T1.15 — Refine location permission flow

**Objective:** Close product-spec.md §4.15 — current flow only
distinguishes Always vs Denied; this task adds explicit handling for
While Using.

**Scope:**
- Yang dikerjakan: distinct handling/copy for all 3 authorization states
  (`.authorizedAlways`, `.authorizedWhenInUse`, `.denied`/`.restricted`);
  When Using specifically gets an explicit explanation that background
  tracking will not run and an active run can stop tracking if the app is
  backgrounded; an in-app path to open Settings to upgrade to Always.
- Yang TIDAK dikerjakan: any change to the underlying `CLLocationManager`
  wrapper (T0.7) beyond reading its existing `authorizationStatus`.

**Depends on:** T0.7

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.15,
[pre-launch-checklist.md](../../04-quality-security/pre-launch-checklist.md) §3

**Definition of Done:**
- [x] All 3 authorization states produce visibly distinct UI copy, not
      just a binary granted/denied treatment — `LocationPermissionNotice`
      (new, `ios/Laju/Views/LocationPermissionBanner.swift`):
      `.authorizedAlways` → no notice (ideal state), `.authorizedWhenInUse`
      → `.whileUsingOnly` copy, `.denied`/`.restricted` → `.denied` copy;
      `.notDetermined` also renders nothing (the system prompt itself is
      the notice at that moment). Wired into `RunTrackingView` as a
      banner below the top status row. Tested:
      `LocationPermissionNoticeTests` (6 tests, including that the two
      notices' title/message differ)
- [x] While Using state explicitly warns about background tracking
      limitations, not a silent limitation the user discovers mid-run —
      `.whileUsingOnly.message`: "Tracking berhenti kalau kamu kunci
      layar atau pindah app saat run aktif..."; the banner is persistent
      (shown whenever `authorizationStatus == .authorizedWhenInUse`), not
      a one-time dismissible toast, so it stays visible through an
      active run rather than only appearing once at grant time
- [x] A Settings deep link is reachable from within the app to upgrade
      permission, without requiring reinstall — `LocationPermissionBanner`'s
      "Buka Pengaturan" button opens `UIApplication.openSettingsURLString`
      via SwiftUI's `openURL` environment action, shown on both the
      While Using and Denied notices

**Partially device-verified 2026-09-14**: device reconnected later in the
session and the build/install/launch cycle is confirmed clean, but the
banner is only visible when authorization is While Using or Denied —
this device's location permission was already `.authorizedAlways` from
earlier sessions, so the banner didn't render on this particular launch.
The banner's copy/logic is unit-tested (`LocationPermissionNoticeTests`);
actually seeing it and tapping "Buka Pengaturan" still needs a hands-on
pass with permission manually reset to While Using/Denied first
(Settings → Laju → Location).

---

### T1.16 — Notification permission + streak reminder

**Objective:** Close product-spec.md §4.16 — local notification only, no
backend, since streak is already computed entirely on-device (T1.1/T1.4).

**Scope:**
- Yang dikerjakan: `UNUserNotificationCenter` permission request at a
  contextual point (not app-launch with no explanation); reminder
  scheduling logic per tech-spec.md §5.2 — schedules `UNCalendarNotificationTrigger`
  for **N days ahead at once** (2026-09-13, Round 7 finding B7-6: a
  design that only reschedules "on run completion and app foreground"
  logically can never help the exact user it targets — someone who
  hasn't opened the app in days), re-derived/cancelled-and-rebuilt on
  every run completion and app foreground using `StreakTracker`'s
  (T1.4) today-check query; a user with `streakDays = 0` (never run) gets
  no reminder — this feature protects an existing streak, it doesn't
  drive first-run acquisition (product-spec §4.16, N7-12).
- Yang TIDAK dikerjakan: any push/server-side notification infrastructure
  — explicitly local-only, consistent with Fase 1 staying backend-free.

**Depends on:** T1.4

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.16,
[tech-spec.md](../../02-architecture/tech-spec.md) §5.2

**Implementation notes (2026-09-14):** `NotificationScheduling` (protocol
over `UNUserNotificationCenter`, new) + `StreakReminderScheduler` (new) —
`reschedule(currentStreakDays:hasRunToday:)` always `removeAllPending()`
first, then (only if `currentStreakDays > 0`) schedules one
`UNCalendarNotificationTrigger` per day, each with its own per-date
identifier (`streak-reminder-YYYY-MM-DD`), at `reminderHour` (20:00
local). Called from `RunViewModel.stop()` (using that run's own final
`streakDays` + whether THIS run itself qualified) and from `LajuApp`'s
`scenePhase` becoming `.active` (app foreground) — both reschedule
triggers from tech-spec.md §5.2 step 1. Permission requested contextually
from a new `streakReminderPrompt` on `RunSummaryView`, shown only when
`summary.streakDays >= 1` AND notification authorization is still
`.notDetermined` — never at app launch.

**Critical bug found and fixed in code review (2026-09-14, same day):**
the original implementation only ever rebuilt the window from tomorrow
onward (`offset 1...daysAhead`), relying entirely on "today's own
reminder was already scheduled by a prior day's call." But `reschedule`
also unconditionally `removeAllPending()`s on EVERY call, including a
plain app foreground with no run — so a user who simply opened the app
today, before running, would have today's already-scheduled reminder
wiped with nothing re-added, silently losing that evening's warning.
Worse, `LajuApp`'s foreground handler computed the streak via
`StreakTracker.currentStreakDays(asOf: Date())`, which returns 0
whenever today has no qualifying run yet — so `reschedule(currentStreakDays:
0)` would ALSO refuse to reschedule at all, compounding the bug. Net
effect: a real, active streak got zero reminder the moment the user did
anything short of a full day of not touching the app at all — the
opposite of the feature's purpose. **Fix:** `reschedule` gained
`hasRunToday: Bool` — when `false`, today (offset 0) is included in the
rebuilt window; `LajuApp` now uses `PersistenceController.priorStreakDays`
(streak ending yesterday, the query `RunViewModel`/`RunRecovery` already
use for this exact reason) instead of the naive `currentStreakDays`.
Regression test added: `StreakReminderSchedulerTests
.testForegroundBeforeRunningTodayStillHasTodaysReminderScheduled`,
reproducing the exact yesterday-schedules→today-foregrounds sequence.

**Definition of Done:**
- [x] Notification permission requested with contextual framing, not
      unconditionally on first launch — `RunSummaryView.streakReminderPrompt`,
      gated on `streakDays >= 1 && notificationAuthStatus == .notDetermined`;
      explains why ("Aktifkan reminder — Laju akan ingetin kamu kalau
      belum lari hari ini...") before the button triggers the system
      prompt. Never called from `LajuApp`/onboarding.
- [x] A reminder fires only when today has no completed run and an active
      streak (≥1 day) is at risk of breaking — `currentStreakDays == 0`
      schedules nothing (`StreakReminderSchedulerTests
      .testZeroStreakSchedulesNothing`); any streak ≥1 schedules the full
      window (`testActiveStreakWithRunTodayExcludesTodayFromTheWindow`,
      `testActiveStreakWithoutRunTodayIncludesTodayInTheWindow`)
- [x] No reminder fires on a day the user already completed a run, and
      none fire at all if notification permission was denied — completing
      a qualifying run passes `hasRunToday: true`, correctly excluding
      today from the rebuilt window; denied permission means
      `SystemNotificationScheduler`'s `add(request:)` calls are silently
      no-ops at the OS level (standard `UNUserNotificationCenter`
      behavior) — no app-side special-casing needed or added
- [x] A reminder still fires on a day the app was NOT opened at all, AND
      survives a plain foreground before that day's own run — the
      critical bug above (found same-day, fixed) was exactly this DoD
      item failing silently. `testForegroundBeforeRunningTodayStillHasTodaysReminderScheduled`
      is the regression test for it.
- [x] Reminder fires at the configured evening local time and never
      stacks duplicate notifications on reschedule (same identifier
      convention reused, not accumulated) — `testScheduledTimeUsesTheConfiguredReminderHour`
      (hour=20, minute=0); `testReschedulingDoesNotStackDuplicates` (two
      reschedule calls still leave exactly `daysAhead` pending, not 2×)

**Device status (2026-09-14):** build/install/launch confirmed clean on
physical device (console showed a normal GPS cycle, no crash). The
end-to-end notification behavior itself (permission prompt appearing,
a reminder actually arriving next evening) needs real elapsed time and a
person watching the device — not verifiable from this session in the
same pass as the code change.

---

### T1.17 — Internal dogfood QA pass (phase DoD gate)

**Renumbered from T1.7 (2026-09-12)** when T1.8-T1.16 were inserted ahead
of it, so the phase gate task keeps its role as the last task in the
file, depending on everything before it — same reasoning as B6-5's
original fix (audit-report.md), extended to the new tasks.

**Objective:** Verify the actual acceptance bar from development-plan.md
Fase 1 — the point where the core hypothesis becomes testable — before
starting backend work.

**Scope:**
- Yang dikerjakan: complete a manual multi-day test (real or
  time-manipulated) of doing several runs, confirming points/level/streak
  accumulate consistently and correctly against the formula, and that the
  9 additions (T1.8-T1.16) behave correctly together in that same
  multi-day usage (not just in isolation); log any discrepancy as a bug
  against the relevant task, not a new feature.
- Yang TIDAK dikerjakan: any new functionality — this is verification
  only.

**Depends on:** T1.2b, T1.4, T1.5, T1.6, T1.8, T1.9, T1.10, T1.11, T1.12,
T1.13, T1.14, T1.15, T1.16

**Reference:** [development-plan.md](../development-plan.md) Fase 1 DoD

**Definition of Done:**
- [ ] At least 5 runs completed across at least 3 distinct days, all
      producing correct points/level/streak per the formula
- [ ] No data loss or calculation inconsistency observed across app
      restarts
- [ ] Live map, static map, splits, auto-pause, elevation, audio cues,
      crash recovery, permission flow, and streak reminder (T1.8-T1.16)
      all exercised at least once during this pass with no regression to
      the core points/level/streak loop
- [ ] **Every row in [deferred-manual-tests.md](../../04-quality-security/deferred-manual-tests.md)
      belonging to a Fase-1 task is either Pass, or explicitly documented
      as an accepted limitation** (the pattern T0.9's battery item already
      set) — this gate cannot be signed off with a deferred test silently
      still outstanding. Today that means T1.8's battery re-measurement and
      T1.13's screen-locked audio check specifically: neither is implied by
      the "exercised at least once" item above, since one is a measurement
      and the other requires the screen to be locked (added 2026-09-17)
- [ ] Internal dogfooding sign-off recorded (who tested, on what device,
      any issues found and resolved)
