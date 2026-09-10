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

**Reference:** [tech-spec.md](../tech-spec.md) §2.2–2.3, §2.2b

**This task owns authoring `shared/point-formula.fixtures.json`'s
content** (T0.1 only creates it as an empty `[]` placeholder) — since the
fixture is now the *only* mechanism preventing client/server point
divergence post-pivot (no more literal shared source file), an empty or
sparse fixture would make the parity guarantee vacuous.

**Definition of Done:**
- [ ] Function signature and constants (`streakBonusPerDay`, pace
      brackets) match tech-spec.md §2.3 exactly
- [ ] Unit tests cover: each pace bracket boundary, streak cap at 7 days,
      zero-distance edge case
- [ ] `shared/point-formula.fixtures.json` populated with ≥1 vector per
      pace bracket (covering both sides of each half-open boundary),
      streak days at 0/1/7/8, and a zero-distance case — not left as the
      empty placeholder T0.1 created
- [ ] `XCTest` fixture-parity test passes against
      `shared/point-formula.fixtures.json` (tech-spec.md §2.2b), and fails
      if the fixture file is empty (row-count assertion, so an
      accidentally-reverted fixture can't silently pass)

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

**Reference:** [product-spec.md](../product-spec.md) §4.3 AC1

**Definition of Done:**
- [ ] Summary screen appears within 2 seconds of stopping a run
      (product-spec AC 4.3.1)
- [ ] Displayed points match `calculatePoints` output for the recorded
      distance/pace
- [ ] `estimatedPoints` persisted on the `Run` entity

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

**Reference:** [product-spec.md](../product-spec.md) AC 4.2.3

**Definition of Done:**
- [ ] User can pause and resume a run any number of times from the UI,
      visually distinct from stop
- [ ] `durationSeconds` and `distanceMeters` correctly exclude paused
      time — verified against a manually timed pause/resume cycle
- [ ] No new Core Data `gpsRoute` points are recorded during a paused
      interval (verified directly against the local persistent store)
- [ ] `estimatedPoints` (T1.2) does not change while paused and resumes
      updating correctly after resume

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

**Reference:** [product-spec.md](../product-spec.md) §4.4,
[database-api-spec.md](../database-api-spec.md) §1 (Level note)

**Definition of Done:**
- [ ] Level correctly derived from cumulative local points against the
      threshold table
- [ ] `levelThresholds` values match database-api-spec.md §1's table
      exactly, row for row — verified by a test, not just visually
- [ ] A basic visual/notification appears when a run causes a level-up
      (product-spec AC 4.4.2)

---

### T1.4 — Local streak tracking feeding streak_bonus

**Objective:** Wire the streak variable that T1.1's formula already
supports but T1.2 stubbed out.

**Scope:**
- Yang dikerjakan: compute `streakDays` from consecutive-day run history
  in local Core Data, pass real value into `calculatePoints` on the
  summary screen.
- Yang TIDAK dikerjakan: any streak-specific UI beyond what product-spec
  §3 calls "streak indicator" (Should-have, can be minimal — a number is
  enough for this task).

**Depends on:** T1.2

**Reference:** [tech-spec.md](../tech-spec.md) §2.1, §2.2

**Definition of Done:**
- [ ] Streak count correctly resets when a day is missed (verified with
      manually seeded run timestamps)
- [ ] Streak bonus in the displayed point estimate matches
      `calculatePoints` given the computed streak

---

### T1.5 — Local run history screen

**Objective:** Let the user see past runs — the Should-have from
product-spec §3 that also doubles as a debugging/QA surface for this
phase.

**Scope:**
- Yang dikerjakan: SwiftUI list screen (`@FetchRequest` or
  `NSFetchedResultsController`-backed ViewModel) reading all local `Run`
  entities, showing date, distance, pace, estimated points.
- Yang TIDAK dikerjakan: filtering/sorting beyond reverse-chronological,
  any server sync status indicator (no server yet).

**Depends on:** T1.2

**Reference:** [product-spec.md](../product-spec.md) §3 (Should-have: run history)

**Definition of Done:**
- [ ] All local runs appear in the list, most recent first
- [ ] Displayed values match what's stored in Core Data for each run

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

**Reference:** [product-spec.md](../product-spec.md) §4.4 AC3

**Definition of Done:**
- [ ] Progress bar and level shown match T1.3's derivation for the
      current local run history
- [ ] Screen updates immediately after a new run is completed (no app
      restart needed)

---

### T1.7 — Internal dogfood QA pass (phase DoD gate)

**Objective:** Verify the actual acceptance bar from development-plan.md
Fase 1 — the point where the core hypothesis becomes testable — before
starting backend work.

**Scope:**
- Yang dikerjakan: complete a manual multi-day test (real or
  time-manipulated) of doing several runs, confirming points/level/streak
  accumulate consistently and correctly against the formula; log any
  discrepancy as a bug against the relevant task (T1.1–T1.6), not a new
  feature.
- Yang TIDAK dikerjakan: any new functionality — this is verification
  only.

**Depends on:** T1.2b, T1.4, T1.5, T1.6 (T1.2b added — it's the sole owner
of AC 4.2.3 and was previously a graph leaf nothing gated on, the same
failure mode the AC coverage matrix exists to catch)

**Reference:** [development-plan.md](../development-plan.md) Fase 1 DoD

**Definition of Done:**
- [ ] At least 5 runs completed across at least 3 distinct days, all
      producing correct points/level/streak per the formula
- [ ] No data loss or calculation inconsistency observed across app
      restarts
- [ ] Internal dogfooding sign-off recorded (who tested, on what device,
      any issues found and resolved)
