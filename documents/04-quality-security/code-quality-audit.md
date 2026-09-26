# Laju App — Swift Concurrency & Pattern Audit (Fase 1 code)

Created 2026-09-17. A retrospective audit of the Fase 1 Swift code as it exists on disk — not a review of planned work, and **not a rewrite**. No source file was modified as part of this audit. Every finding below is a report awaiting a decision.

Depends on: [tech-spec.md](../02-architecture/tech-spec.md), [architecture.md](../02-architecture/architecture.md), [adr/README.md](../02-architecture/adr/README.md), [security-review.md](./security-review.md)

**Method**: the three ECC skills `swift-concurrency-6-2`, `swiftui-patterns`, and `swift-actor-persistence` were applied as review lenses, supplemented by direct reading of every file in the tracking path and by a real build. §6 states exactly which finding came from which lens and which were manual.

---

## 0. Baseline: the project already passes the bar most Swift 6 audits are looking for

Before any finding, the most important verified fact, because it sets the severity ceiling for everything below.

`project.yml` sets, for every target:

```yaml
SWIFT_VERSION: "6.0"
SWIFT_STRICT_CONCURRENCY: complete
SWIFT_TREAT_WARNINGS_AS_ERRORS: YES
```

A full build was run against this configuration as part of this audit:

```
** BUILD SUCCEEDED **
```

Zero errors, zero warnings. This is Swift 6 language mode with complete strict-concurrency checking and warnings promoted to errors — the strictest standard configuration available at this Swift version.

**The direct consequence: there is no compiler-detectable data race anywhere in this codebase.** Every question in this audit's brief of the form "is there a data race in X" has already been answered `no` by the compiler, under a configuration that makes such a race a build failure rather than a warning. That is a genuinely strong baseline and not the common case.

What follows is therefore **not** a list of races. It is a list of places where safety currently rests on an assumption the compiler was never asked to check, plus a set of correctness and performance findings that strict concurrency does not model at all.

---

## 1. Severity convention

Same three-tier scale as [security-review.md](./security-review.md) §0, for consistency across both documents produced in this round.

| Tier | Meaning |
|---|---|
| **Blocker** | A real defect with a concrete failure path that silently defeats a guarantee the project has explicitly designed for. |
| **Warning** | A real exposure or fragility. Correct today, but correct by assumption or by accident rather than by construction. |
| **Note** | Recorded for completeness — an accepted constraint, a forward-looking observation, or a verification that an area is sound. |

Findings are numbered `CQ-n`.

---

## 2. Concurrency and isolation

### CQ-1 — Main-thread safety is assumed everywhere and declared nowhere — **Warning**

No type in the GPS → state → persistence path carries any isolation annotation:

| Type | File | Isolation |
|---|---|---|
| `RunViewModel` | `ios/Laju/ViewModels/RunViewModel.swift:9` | none |
| `LocationTrackingService` | `ios/Laju/Services/Location/LocationTrackingService.swift:8` | none |
| `AutoPauseWatchdog` | `ios/Laju/ViewModels/AutoPauseWatchdog.swift:7` | none |
| `RoutePointBuffer` | `ios/Laju/ViewModels/RoutePointBuffer.swift:6` | none |

All four are plain non-`Sendable` `final class`es, and all four mutate `@Published` state or Core Data objects.

They pass complete strict-concurrency checking **not because their isolation was proven correct, but because they never cross an isolation boundary the compiler examines.** The GPS data path is `CLLocationManagerDelegate` → `PassthroughSubject.send` → `.sink { }`, and Combine's `sink` closure is not `@Sendable`, so no boundary check ever occurs. The code is single-threaded, so the compiler has nothing to complain about — and equally, nothing to verify.

The actual main-thread guarantee is a runtime convention with two links, both currently sound:

1. `CLLocationManager` delivers delegate callbacks on the queue/run loop on which the manager was created. The manager is created in `LocationTrackingService.init()` (`LocationTrackingService.swift:19`), and every production construction site is a SwiftUI `@StateObject` initializer — `RunTrackingView.swift:15` and `OnboardingContainerView.swift:14` — i.e. on the main thread. So callbacks arrive on main.
2. The two timers both specify `on: .main` explicitly (`RunViewModel.swift:160`, `AutoPauseWatchdog.swift:28`).

Link 2 is declared in code. **Link 1 is not written down anywhere, and is not enforced by anything.** If any future code constructs `LocationTrackingService` off the main thread — a background prewarm, a `Task.detached`, a future headless sync path — every `@Published` mutation in both classes silently moves off-main. SwiftUI's main-thread requirement is then violated, the symptom is intermittent UI corruption or a crash in a release build, and **the build stays green**, because nothing in the type system was ever told the assumption existed.

The fix is close to free, since everything already runs on main: annotate `RunViewModel` and `LocationTrackingService` `@MainActor`. One wrinkle is worth stating so the fix is not mis-scoped — `CLLocationManagerDelegate` is a non-isolated protocol, so under Swift 6.0 a `@MainActor` `LocationTrackingService` must mark its delegate methods `nonisolated` and enter main-actor context explicitly via `MainActor.assumeIsolated { }`. That is the correct outcome rather than a workaround: it converts today's invisible assumption into a documented, runtime-checked one. §6's toolchain note describes an option that removes the wrinkle entirely.

### CQ-2 — `RoutePointBuffer.flush` can silently destroy an entire recorded route, by two independent paths — ~~**Blocker**~~ **RESOLVED 2026-09-22**

`ios/Laju/ViewModels/RoutePointBuffer.swift:24-30`:

```swift
func flush(into run: Run) {
    guard !pending.isEmpty else { return }
    var existing = GPSPoint.decodeRoute(from: run.gpsRoute)
    existing.append(contentsOf: pending)
    run.gpsRoute = try? JSONEncoder().encode(existing)
    pending.removeAll()
}
```

This is the single write path for `Run.gpsRoute`, and it is the mechanism T1.14's crash-recovery design depends on. It has two independent silent-total-loss paths:

**(a) Decode failure silently truncates the route to just the pending points.** `GPSPoint.decodeRoute` ends in `?? []` — any decode failure returns an empty array rather than signalling. `flush` cannot distinguish "this run has no points yet" from "this run's existing points could not be read." In the second case it appends `pending` to an empty array and writes the result back, **replacing the entire prior route with only the last ≤20 points.** No error, no log, and the run continues looking healthy. This path needs no exotic trigger — any partial write, any future model change, any corruption is sufficient.

**(b) Encode failure nils the route entirely.** `try?` on the assignment means a throw assigns `nil` to `run.gpsRoute`, discarding every point ever recorded for that run — and the very next line, `pending.removeAll()`, discards the in-memory copy too. Both copies gone in two consecutive statements. `GPSPoint`'s `lat`, `lng`, and `elevation` are plain `Double`, and `JSONEncoder`'s default `nonConformingFloatEncodingStrategy` is `.throw`, so a non-finite value throws. The upstream accuracy filter (`horizontalAccuracy < 0`, `LocationTrackingService.swift:164`) rejects most invalid fixes, which makes this path unlikely — but not structurally impossible, and the consequence does not scale with the likelihood.

Rated **Blocker** on path (a), which requires no unusual precondition and defeats the exact guarantee T1.14 was built to provide: that a run survives a force-kill. A durability mechanism whose failure mode is silent, total, and indistinguishable from success is the wrong shape regardless of how often it fires.

Recording clearly, per the audit-only instruction: **no fix was applied.** The shape of a fix is straightforward — make `flush` fail loudly rather than lossily, distinguish "empty" from "unreadable", and never overwrite a non-`nil` `gpsRoute` with `nil` — but that is a code change awaiting a decision, not part of this audit.

**Status update, 2026-09-22 — fix implemented, verification pending.** With the user's go-ahead, `RoutePointBuffer.flush` (`ios/Laju/ViewModels/RoutePointBuffer.swift`) and `GPSPoint.decodeRoute`/new `decodeRouteStrict` (`ios/Laju/Models/GPSPoint.swift`) were changed exactly along the shape above: a new `RouteDecodeResult` (`.noRoute` / `.decoded` / `.corrupted`) replaces the old `?? []` collapse so `flush` can tell "empty run" apart from "undecodable bytes," and `flush` now returns a `RouteFlushResult` — an undecodable existing route or an encode failure (e.g. a non-finite `Double`) aborts the flush with a loud `print` instead of silently truncating or nil-ing `run.gpsRoute`, and `pending` is only cleared once the merge is actually persisted. Five new regression tests were added in `ios/LajuTests/RoutePointBufferTests.swift` covering both silent-loss paths plus the normal/no-op/append-across-flushes cases.

Caught and fixed on a second read-through, same day, before handoff: the first version of this fix used `assertionFailure` (in addition to `print`) on both failure paths, on the theory that "fail loudly" meant crash-loud. That was wrong and has been removed — `assertionFailure` traps in Debug builds, which is what `xcodebuild test` and every dogfood build (T1.17) run under. It would have turned the exact scenario this fix exists to survive (a corrupted route, an unencodable point) into an app crash mid-run instead of a logged, data-preserving no-op — a worse failure mode than the one being fixed, and one that would have shown up as a crashing test rather than a clean signal. `print`-only logging is now the loud-but-non-fatal signal both production call sites and the tests rely on.

**Closed 2026-09-22 — real evidence obtained via CI, not "should work."** PR opened from `luvfr` → `main` specifically to trigger `ci-ios.yml`'s `pull_request` check (a plain push to `luvfr` doesn't trigger CI — its `push` trigger is scoped to `main` only): [riporipo223/laju-app#1](https://github.com/riporipo223/laju-app/pull/1). First run ([35717238185](https://github.com/riporipo223/laju-app/actions/runs/35717238185)) genuinely failed — a real SwiftFormat `redundantThrows` violation in the new test file, caught and fixed (one-line, `RoutePointBufferTests.swift:34`, HANDOFF §1's mechanical-fix exception), amended into the same commit, force-pushed. Second run ([35717568035](https://github.com/riporipo223/laju-app/actions/runs/35717568035), commit `cecba05`) passed clean: SwiftLint 0 violations, SwiftFormat clean, and **`Build + test` actually ran** — `Executed 191 tests, with 0 failures (0 unexpected)` / `** TEST SUCCEEDED **`. The 5 CQ-2 regression tests specifically ran and passed, with log output confirming the real defensive behavior fired (not just "didn't crash"):
```
RoutePointBuffer.flush: failed to encode route for run ... — keeping the previously-persisted gpsRoute untouched; 1 pending point(s) kept for retry: invalidValue(nan, ...)
RoutePointBuffer.flush: existing gpsRoute for run ... could not be decoded — refusing to overwrite it; 1 pending point(s) kept for retry
```
**Merged 2026-09-23** ([riporipo223/laju-app#1](https://github.com/riporipo223/laju-app/pull/1), commit `99cd7ef`). Before merging, an independent audit found and fixed one thing CQ-2's own evidence didn't cover: `Build + test` on the PR's next real code change (Task C, `6a4cfb4`) failed with a genuine Swift 6 data-race error in the newly-added `LocationAuthorizationObserver.swift` — a `CLLocationManagerDelegate` callback's own `manager` parameter (non-Sendable, task-isolated) was read inside a `MainActor.assumeIsolated` closure. Fixed by reading `self.manager` (already actor-isolated) instead of the closure parameter. Also found: `LocationAuthorizationObserver.swift`/`LeaderboardLockedView.swift` shipped with zero test coverage, violating repo-coding-rules.md §4's PR checklist — closed with `LocationAuthorizationObserverTests.swift` (5 tests, the pure `LeaderboardAccessState.state(for:)` mapping). Final CI on the merged tip: iOS 187/187, Backend 292/292 (real Supabase integration suite, run against the actually-migrated production schema).

### CQ-3 — `@unchecked Sendable` on `StreakReminderScheduler` extends a safety promise to types it does not control — **Warning**

`ios/Laju/ViewModels/StreakReminderScheduler.swift:14` declares `final class StreakReminderScheduler: @unchecked Sendable`, justified in the doc comment (lines 10-13) as: "all stored state (`notifications`, `calendar`) is set once at init and never mutated afterward."

That justification is true of the *references* — both are `let` — but `@unchecked Sendable` is a claim about safe concurrent access to the *referents*. The stored `notifications` is of type `any NotificationScheduling`, and `ios/Laju/ViewModels/NotificationScheduling.swift:6` declares that protocol with **no `Sendable` constraint**. The unchecked conformance therefore silently extends the Sendable promise to whatever conforms.

- **Production is sound**: `SystemNotificationScheduler` wraps `UNUserNotificationCenter`, which is thread-safe, and holds no mutable state of its own.
- **Tests are not**: both spies conforming to this protocol hold mutable state — `LajuTests/StreakReminderSchedulerTests.swift:6-12` declares `scheduledIdentifiers: [String]`, `scheduledDateComponents: [String: DateComponents]`, `requestAuthorizationCallCount`, `var authorizationResult`, `var authorizationStatusToReturn`; `LajuTests/RunViewModelStreakReminderTests.swift:6-8` similarly. Each is mutated from the scheduler's calls while the enclosing type advertises itself as `Sendable`.

The correct assertion is one word — `protocol NotificationScheduling: Sendable` — which would make the compiler verify what the comment currently asserts on the compiler's behalf, and would flag the spies so they can be made explicitly safe. As written, the `@unchecked` escape hatch is doing more work than its justification covers.

### CQ-4 — `PersistenceController`'s `nonisolated(unsafe)` is correctly reasoned — **Note**

Recorded as a positive verification so it is not re-flagged. `ios/Laju/Services/Persistence/PersistenceController.swift:22` declares `private nonisolated(unsafe) static let model: NSManagedObjectModel`, with an unusually complete justification (lines 8-21) covering both *why the shared instance is necessary* (re-parsing `Laju.momd` per `init` yields distinct model objects, breaking Core Data's `+entity` resolution when the app's `.shared` and a test's in-memory controller coexist) and *why the unsafe annotation is sound* (`NSManagedObjectModel` is immutable once loaded but not `Sendable`, so the compiler cannot verify it).

Both halves check out. The model is only ever read — passed to `NSPersistentContainer(name:managedObjectModel:)` at line 33 and never mutated after the initializing closure returns. This is the escape hatch used correctly: a narrow exception, documented with its reason, rather than a blanket suppression.

---

## 3. Core Data persistence

### CQ-5 — There are no background contexts, so the cross-context race class does not exist yet — **Note**

The brief asks whether `PersistenceController`'s actor isolation and background-context handling are safe from race conditions. Verified directly across the whole app target:

```
grep -rn "performBackgroundTask\|newBackgroundContext\|\.perform" Laju/   →   no matches
```

There are **no background contexts and no `perform`/`performAndWait` calls anywhere.** Every Core Data operation — `PersistenceController`'s five static query helpers, and all seven `context.save()` sites — runs on `container.viewContext`, on the main thread, per CQ-1's convention.

So the honest answer is that the risk the question targets is not present, because the structure that creates it has not been built. All Core Data access is single-threaded and therefore trivially free of cross-context races.

One forward-looking observation, which is the part worth acting on. `PersistenceController.swift:42` sets:

```swift
container.viewContext.automaticallyMergesChangesFromParent = true
```

Nothing currently writes to a parent or background context, so this line is **inert today**. It becomes live the moment Fase 2's sync layer introduces its first background write — at which point merge behaviour activates silently, with no code change at the call site and no signal that the concurrency model just changed. That is the point at which context confinement needs an actual design, and it will arrive without announcing itself. Worth a note in the Fase 2 sync task now, while the reason is fresh.

### CQ-6 — Seven `try? context.save()` sites discard persistence failures — **Note**

All seven save sites swallow their error:

| Site | Purpose |
|---|---|
| `RunViewModel.swift:118` | initial `Run` row at Start |
| `RunViewModel.swift:186` | duration persist on pause |
| `RunViewModel.swift:239` | final points/duration at stop |
| `RunViewModel.swift:281` | `periodicFlush` — the durability timer |
| `RunViewModel.swift:382` | count-triggered flush |
| `RunRecovery.swift:67` | recovery finalization |
| `PersistenceController.swift:55` | `SyncMeta` creation |

A failed save is indistinguishable from a successful one at every one of them, including `periodicFlush`, whose entire documented purpose is durability against force-kill.

Rated **Note** rather than Warning, deliberately: saves on a healthy main-queue `viewContext` rarely fail, and the periodic flush retries implicitly on its next tick, so a transient failure self-heals. The real gap is diagnostic — a *persistent* failure (disk full, store corruption, migration failure) would produce a run that appears to be recording normally and is in fact persisting nothing, with no log line anywhere to explain it afterwards. Logging the error at these sites costs nothing and would make that scenario debuggable. Contrast with CQ-2, which is a Blocker precisely because its failure is not transient and not self-healing.

### CQ-7 — Full-route re-encode on every flush is O(n²) main-thread work — **Warning**

`RoutePointBuffer.flush` decodes the entire existing route, appends the pending points, and re-encodes the entire route (`RoutePointBuffer.swift:24-30`). It is called from two triggers, both on the main thread:

- every 20 accepted points (`saveEveryNPoints`, `RunViewModel.swift:379`)
- every 5 seconds (`flushIntervalSeconds`, `RunViewModel.swift:277`)

and each call is followed by `context.save()`, which writes the whole re-encoded blob — a Core Data Binary attribute — to disk.

Cost with the project's own longest real run as the reference point (the 24km calibration run, pk=81). `distanceFilter` is 10m (`LocationTrackingService.swift:67`), so 24km yields on the order of 2,400 fixes before the accuracy and jitter filters reject any. That gives roughly 120 count-triggered flushes, plus one every 5 seconds for the run's full duration, each handling an average of half the accumulated route — on the order of several hundred thousand point encode/decode operations across the run, all on the main thread. The *last* flushes are the expensive ones: each decodes ~2,400 points, re-encodes ~2,400 points, and writes a blob on the order of 200KB, synchronously, while the user is looking at a live-updating map and stats screen.

It scales quadratically with run length, so it degrades exactly where it is least acceptable — a marathon is roughly four times worse than this already-measured case. If any late-run UI hitching has been observed on device, this is the first thing to look at.

Worth noting what is *not* wrong here: the incremental-flush design itself is correct and well-reasoned (it exists so a force-kill loses at most one interval, per the class documentation and Round 7 B7-2). The finding is narrowly about the append implementation — full decode/re-encode of an accumulating array — not about the flush strategy.

---

## 4. SwiftUI patterns

### CQ-8 — `ObservableObject`/`@Published`/`@StateObject` is legacy-by-constraint, not by oversight — **Note**

The `swiftui-patterns` lens flags `ObservableObject`, `@Published`, `@StateObject`, and `@EnvironmentObject` as anti-patterns in new code, to be migrated to the `@Observable` macro. This codebase uses the older wrappers throughout.

**That migration is unavailable here.** The Observation framework requires iOS 17, and the deployment target is locked at iOS 16.0 (`project.yml`, both targets). That is the same constraint already recorded in ADR-0011, where it forced `MKMapView` over SwiftUI's `Map` because `MapPolyline` is iOS 17+.

Recorded explicitly so a future reviewer applying a generic SwiftUI checklist does not file this as tech debt: the current pattern is the *correct* consequence of a deliberate, documented platform decision (ADR-0001). It becomes reconsiderable only if the deployment target rises, and at that point it should be evaluated as a real migration rather than a lint fix — `@Observable`'s property-level change tracking would be a genuine win for `RunViewModel`, whose many `@Published` properties currently invalidate every observing view on any change.

### CQ-9 — Two independent `LocationTrackingService` instances can exist — **Note**

`RunTrackingView.swift:15` and `OnboardingContainerView.swift:14` each declare their own `@StateObject private var locationService = LocationTrackingService()`, so two instances — and therefore two `CLLocationManager` objects — can exist in one process.

Harmless in practice: onboarding's instance exists only for the permission step and is released when onboarding completes, and the two are never active simultaneously in a way that affects tracking. Recorded because authorization state is consequently tracked in two places, and because the pattern does not extend — a third surface needing location (a settings screen re-checking permission, say) would make the duplication a real source of divergent `authorizationStatus` readings. A single shared instance injected through the environment would be the natural shape if that happens.

**Update, 2026-09-23 — the "does not extend" prediction landed.** Task C of the Local Leaderboard/region reversal (product-spec.md §4.5 AC5) added a third surface: `LeaderboardView` now owns `LocationAuthorizationObserver` (`ios/Laju/ViewModels/LocationAuthorizationObserver.swift`), its own thin `CLLocationManager` wrapper reading only `authorizationStatus`. That is **three** independent `CLLocationManager`-adjacent instances in the process now (`RunTrackingView`'s and `OnboardingContainerView`'s `LocationTrackingService`, plus `LeaderboardView`'s `LocationAuthorizationObserver`). Not fixed as part of that change — deliberately out of scope, flagged in that commit's own message and here for tracking, not drift. Still a Note, not upgraded to Warning: the three cannot disagree (all read the same OS-level authorization state), and `LocationAuthorizationObserver` never calls `startUpdatingLocation`, so it does not introduce the "two tracking sessions" risk CQ-1/CQ-9's original framing was about — it only makes the "single shared instance injected through the environment" fix this entry already recommended cover one more consumer.

## 4a. Backend (added 2026-09-24)

### CQ-10 — `resolve-flagged-runs` cron accepts `Bearer undefined` when `CRON_SECRET` is unset — **Warning** (open, not fixed)

`backend/app/api/cron/resolve-flagged-runs/route.ts` authorizes with `authHeader !== \`Bearer ${process.env.CRON_SECRET}\``. If `CRON_SECRET` is missing in an environment, the template literal becomes the string `"Bearer undefined"`, so a request carrying exactly `Authorization: Bearer undefined` is let in — and this route writes real ledger and trust-score changes (the same blast radius as any write path).

Mitigated today, not closed: production has `CRON_SECRET` set, so the hole only opens in an environment where it is missing (a new preview/dev project, a rotated-and-forgotten variable). Found 2026-09-24 while writing the Club War cron route (T4.2b), which copied the same pattern and was fixed there with a `!secret` guard plus a test for the unset case. **This route is deliberately not changed yet** — recorded as technical debt rather than silently patched outside that task's scope. Fix: the same one-line `!secret ||` guard and the same test.

---

## 4b. iOS — live running metrics (added 2026-09-26)

### CQ-11 — Live/instant pace shown during tracking has no defined calculation method — **RESOLVED 2026-09-26** (`b1ded91`)

Found during a PM product-review session (2026-09-26), reported by real usage: the pace value shown live on the Run Tracking screen (screen 5, element #2 in wireframe-spec.md) "kadang melompat, kadang tidak sesuai dengan kecepatan aslinya" (sometimes jumps, sometimes doesn't match actual speed).

Checked against tech-spec.md and every phase-N task file: **the whole-run average pace used for the point formula (`avg_pace_sec_per_km`, tech-spec.md §2.1/§2.2) is well-specified and stable** (one ratio of two robust totals, computed once at Stop — not affected by this finding). But **the live/instant pace shown during an active run has no documented calculation method anywhere** — no window size, no smoothing rule, unlike `avg_pace_sec_per_km`'s explicit spec.

**Root cause confirmed by code audit, 2026-09-26 (corrects this entry's original speculation below).**
`RunTrackingView.swift`'s `liveSpeedLabel` (formerly `livePaceLabel`) computes
`liveActiveDuration() / (distanceMeters / 1000)` on every UI tick — the **same whole-run cumulative
average** `avg_pace_sec_per_km` uses at Stop, not a last-N-samples calculation as originally
guessed. The jumpiness comes from a different mechanism: early in a run the denominator (elapsed
active duration) is small, so each newly-accepted GPS movement chunk (10-20m steps past the
stationary-anchor filter, `RunViewModel.swift:295-336`) swings the cumulative average sharply;
later in the run, the same-size chunk is diluted by a much larger denominator and barely moves it
— matching the reported "jumps early, settles later" pattern better than a raw-instant-velocity
read would. ~~This is very likely the root cause of the reported jumpiness: without a defined
rule, the implementation most plausibly computes pace from the last one or two GPS samples
directly, which is exactly the kind of raw point-to-point signal the T0.9/T0.8 GPS-noise-filtering
work (tech-spec.md §2.1b) already had to guard `distanceMeters` against.~~

Not a data-correctness bug — `avg_pace_sec_per_km` and `final_points` are computed independently of this live value and are unaffected (confirmed: they derive from total distance/duration, never from the live display). This is a UX-quality gap, and it is now also a **hard prerequisite for product-spec.md §4.29** (the new real-time anti-cheat warning) — building a 5-consecutive-detections-in-2-minutes trigger on top of an unsmoothed, jittery live pace signal would produce false warnings and undermine trust in that feature immediately.

**Suggested direction (not a fix — needs real-device tuning, not decided here):** compute live pace from a rolling window (a fixed recent time span or a fixed number of recent accepted GPS points, recomputed independently each tick) rather than the whole-run cumulative average — the exact window size needs on-device testing, not a guess.

**Fixed 2026-09-26 (`b1ded91`):** replaced the whole-run cumulative average with a rolling window
over the last 30 seconds of confirmed GPS movement (`RollingSpeedCalculator.rollingPaceSecPerKm`),
recomputed fresh every UI tick (`RunTrackingView`'s existing `TimelineView` re-render, no new
timer). The window excludes its own oldest sample's distance from the sum (that distance was
covered before the sample's own timestamp, outside the window's span) — an early implementation
that included it was caught by this fix's own tests before being corrected. Returns `nil` — shown
as a neutral placeholder, not a fallback to the buggy cumulative formula — when there's under 2
samples or under 5 seconds of window span, so the run's first few seconds don't show a wild number
either. **30 seconds is a starting value, not final** — same status as `STREAK_BONUS_PER_DAY`/the
pace-bracket table (tech-spec.md §2.2/§2.3), needs on-device tuning with real run data.

`avg_pace_sec_per_km` and the point formula are completely untouched, as designed — this fix only
changes the live on-screen display during tracking, confirmed by the fix itself never referencing
either.

**Evidence:** 4 new tests in `RollingSpeedCalculatorTests.swift`, TDD (failing first) — reproduces
the exact reported jump with synthetic GPS-derived samples (old cumulative formula's first reading
lands at ~3x true pace; the anchor-settling dead time before the first confirmed movement is
mis-divided into the pace), then proves the rolling window's variance is far lower on the same
input, staying within 60 sec/km of true pace throughout. BUILD SUCCEEDED, 250/250 iOS tests pass.
**Real-device/simulator visual verification NOT done** — no real account exists on a fresh
simulator to reach the Run Tracking screen at all (same disclosed limitation hit during recent
Circle tasks); stated plainly rather than claimed. Re-verify on a real device during an actual run
before tuning the window size.

---

## 5. Findings summary

| ID | Area | Finding | Severity |
|---|---|---|---|
| CQ-2 | Persistence | `RoutePointBuffer.flush` can silently destroy an entire route — decode-failure truncation and encode-failure nil | ~~**Blocker**~~ **RESOLVED 2026-09-22** (PR #1, CI run [35717568035](https://github.com/riporipo223/laju-app/actions/runs/35717568035), 191/191 tests) |
| CQ-1 | Concurrency | Main-thread safety assumed but never declared; no `@MainActor` anywhere in the tracking path | **Warning** |
| CQ-3 | Concurrency | `@unchecked Sendable` on `StreakReminderScheduler` covers an unconstrained protocol; test spies hold mutable state | **Warning** |
| CQ-7 | Performance | Full-route decode/re-encode per flush is O(n²) main-thread work; ~200KB synchronous writes late in a 24km run | **Warning** |
| CQ-10 | Security (backend) | `resolve-flagged-runs` cron accepts `Bearer undefined` if `CRON_SECRET` is unset; mitigated in prod, not fixed (added 2026-09-24) | **Warning** |
| CQ-11 | iOS metrics | Live speed now uses a 30s rolling window (`RollingSpeedCalculator`), not the whole-run cumulative average that caused the reported jumpiness; unblocks T4.22 (product-spec.md §4.29) | **RESOLVED** |
| CQ-4 | Concurrency | `PersistenceController`'s `nonisolated(unsafe)` is correctly reasoned and sound | **Note** |
| CQ-5 | Persistence | No background contexts exist, so no cross-context race exists; `automaticallyMergesChangesFromParent` is inert until Fase 2 | **Note** |
| CQ-6 | Persistence | Seven `try? context.save()` sites discard errors; diagnostic gap, not a correctness one | **Note** |
| CQ-8 | SwiftUI | `ObservableObject` pattern is forced by the iOS 16 target (ADR-0001/ADR-0011), not an oversight | **Note** |
| CQ-9 | SwiftUI | Two `LocationTrackingService` instances can coexist; harmless now, does not extend | **Note** |
| — | Build | **Swift 6 language mode, complete strict concurrency, warnings-as-errors — builds clean** | **Verified sound** |

**Zero open Blockers** (CQ-2 resolved 2026-09-22), ~~three~~ ~~four~~ ~~five~~ four Warnings (CQ-10
added 2026-09-24, CQ-11 added 2026-09-26 and resolved the same day), five Notes.

No code was changed as part of the original audit; CQ-2 was fixed in a later session (2026-09-22, see its status block above) with real CI evidence. The rest are safely deferrable, and CQ-1 is best done together with the toolchain question below.

### A note on what the Blocker is not

CQ-2 is not a concurrency defect, and neither are CQ-6 or CQ-7. That is the shape of this audit's result overall: the project's strict-concurrency configuration genuinely worked, and the compiler caught the entire class of problem it exists to catch. What it cannot model — error handling that discards information, and algorithmic cost — is where every real finding landed. Strict concurrency is necessary and it is doing its job here; it is not sufficient, and this codebase is a clean illustration of the boundary.

---

## 6. Which lens produced which finding

Stated explicitly, per the audit brief.

| Finding | Source |
|---|---|
| CQ-1 | `swift-concurrency-6-2` — its "protect globals/statics with MainActor" and "`nonisolated` to suppress errors without understanding isolation" anti-patterns prompted checking *declared* isolation rather than trusting the clean build. |
| CQ-3 | `swift-concurrency-6-2` — same anti-pattern lens, applied to `@unchecked Sendable` as the escape hatch rather than `nonisolated`. |
| CQ-4 | `swift-concurrency-6-2` — verification pass on the remaining escape hatch. |
| CQ-8 | `swiftui-patterns` — its `@Observable` migration guidance flagged the pattern; the iOS 16 constraint that makes it correct was manual (cross-referenced to ADR-0001/ADR-0011). |
| CQ-9 | `swiftui-patterns` — state-ownership and DI guidance. |
| CQ-2 | **Manual.** No skill covers error-discarding (`try?` / `?? []`) as a durability defect; found by reading the write path end to end. |
| CQ-6 | **Manual**, same reason. |
| CQ-7 | **Manual.** `swiftui-patterns`' "avoid expensive work in `body`" is adjacent but does not apply — the cost is in a timer callback, not a view body. Found by tracing `flush`'s algorithmic cost against the project's own longest real run. |
| CQ-5 | **Manual**, with `swift-actor-persistence` as a partial lens — see below. |

**On `swift-actor-persistence` specifically**: its core pattern (an `actor` wrapping an in-memory cache over file-backed JSON) **does not apply to this codebase**, and adopting it would be wrong. Core Data has its own concurrency model — context confinement with `perform`/`performAndWait` — and wrapping an `NSManagedObjectContext` in an actor is a known anti-pattern that fights the framework rather than using it. The skill's *principles* were still useful, and did real work: its emphasis on atomic writes preventing partial-write corruption on crash is what prompted examining `flush`'s write path in the first place, which is how CQ-2 was found. Recorded honestly: the skill's pattern was rejected as unsuitable, its durability principle was applied and productive.

**On `swift-concurrency-6-2` and the toolchain — one recommendation that came from the skill and has no finding number**, because it is a configuration decision rather than a defect:

The skill documents Swift **6.2**'s Approachable Concurrency — specifically MainActor default isolation (SE-0466), under which every type in an app target is main-actor-isolated by default. The project is on `SWIFT_VERSION: "6.0"`, so none of it is currently available.

This matters because MainActor-by-default is a precise description of what this codebase already does by convention. Adopting it would convert CQ-1's undocumented, unenforced assumption into a compiler-enforced guarantee with close to zero code changes — the code already runs entirely on main. It also removes CQ-1's one awkward edge: Swift 6.2's isolated conformances allow `extension LocationTrackingService: @MainActor CLLocationManagerDelegate` directly, instead of the `nonisolated` + `MainActor.assumeIsolated` dance that a 6.0 fix requires.

This is a toolchain and build-settings decision with its own risk surface (a Swift version bump touches everything), so it is raised as an option to evaluate deliberately, not a recommendation to act on immediately. But if CQ-1 is going to be addressed at all, the two questions should be decided together rather than fixing CQ-1 twice.

---

## 7. Relationship to the security review

One finding in [security-review.md](./security-review.md) is a code-level concern that belongs to both documents, and is recorded there rather than duplicated here: **SEC-2**, the absence of an explicit `NSFileProtection` class on the Core Data store. It is a security finding by consequence (precise location history at rest) and a persistence-configuration finding by mechanism, and its resolution is constrained by the same background-write requirement that shapes this document's concurrency picture — a store that must accept writes while the device is locked cannot use `NSFileProtectionComplete`.

No finding in this document changes any finding in that one. CQ-5's confirmation that all Core Data access is main-thread and single-context does, however, *simplify* SEC-2's eventual fix: with no background context to coordinate, the protection-class choice applies to exactly one store description and one access pattern.
