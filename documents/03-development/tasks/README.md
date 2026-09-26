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
[product-spec.md](../../01-product/product-spec.md) §4 must have a row below with at
least one owning task and a real DoD item that verifies it — not just a
task that touches the feature. Adding or changing an AC in product-spec.md
§4 must update this table in the same change. A `Partial` status means an
owning task exists but no DoD item verifies the AC's specific claim
(usually a number or an explicit behavioral assertion) — these are
tracked, not silently treated as done.

| AC | Requirement (short) | Owning task(s) | Verified by DoD? |
|---|---|---|---|
| 4.1.1 | Sign-up in ≤3 steps | T2.3 | **Partial** — T2.3's DoD doesn't assert the step count |
| 4.1.2 | ~~Region required before first run submits~~ | ~~T2.4, T2.5, T3.1~~ | **REVERSED 2026-09-22** (D1 reversal, PM sign-off) — region requirement removed entirely, not just deferred; consequence of Local Leaderboard's cancellation (4.6.x). Replacement: 4.5.5 (location-permission gate). Was "Yes". **Rework DONE 2026-09-23**: T2.4/T2.5/T3.1's region-validation code fully removed (Task C, `6a4cfb4`), `region_*` columns physically dropped from production (Task B's migration `20260923090000`, applied and verified live — 0 columns remain, constraint rejects a regional insert) |
| 4.1.3 | Login persists across app restarts | T2.3 | Yes |
| 4.2.1 | ≥60 min background tracking, ≤5% distance drift | T0.8, T0.9 | **Partial** — background survival confirmed (~59min, T0.9), battery drain confirmed (3%/hour, T0.9), and distance accuracy has real evidence (T0.8: ~0.15% deviation vs Strava on a ~660m outdoor run), well within 5%; still Partial only because neither task literally asserts "5%" as a numeric pass/fail gate in its own DoD text — all underlying evidence now supports a Yes |
| 4.2.2 | Data survives OS force-kill | T0.9 | Yes |
| 4.2.3 | Start/pause/stop clearly from UI | T1.2b | Yes |
| 4.3.1 | Local point estimate in <2s | T1.2 | Yes |
| 4.3.2 | Final points + reason shown if they differ, incl. later resolution | T2.14, T2.14b, T2.14c, T2.14d | **Partial** — flagged/approved/rejected divergence fully covered; a `validated` run whose points differ due to `trust_multiplier` or sub-`FLAG_THRESHOLD_PCT` exclusion has no owning copy. **2026-09-21:** a real run showed the server awarding no streak bonus (estimate +2.7, awarded 1) — **fixed the same day** (the server now derives the streak; live: estimate 2.58 → awarded 3, tech-spec §2.2), so that particular divergence is gone; the `trust_multiplier` exposure below remains. **Updated 2026-09-17:** `trust_multiplier` is now fully defined (tech-spec §2.4 formula block) and computed by T2.11, so the remaining half of this gap is purely *exposure* — no task owns telling the user "your points were reduced because your trust score is below 1.0" |
| 4.3.3 | Implausible-pace runs don't get full points automatically | T2.7, T2.12a, T2.13 | Yes |
| 4.4.1 | Level from lifetime cumulative points, never resets | T1.3, T2.12c | Yes |
| 4.4.2 | Level-up notification/visual | T1.3 | **Partial** — only asserted for local/offline level-ups; T2.16 (server-backed screen) has no DoD item for a level-up triggered by a later server-side change (e.g. a `flagged` run resolving to `approved`) |
| 4.4.3 | Points-to-next-level visible on profile | T1.6, T2.16 | Yes |
| 4.5.1 | Top N + own rank shown | T2.20 | Yes |
| 4.5.2 | Leaderboard data ≤15 min stale | T2.18, T2.20 | Yes |
| 4.5.3 | Leaderboard scoped to active season | T2.18 | Yes |
| 4.5.4 | Freemium sees own **Season League** only; Premium unlocks all leagues on Global ("tier" = Season League, tech-spec.md §2.5; revised 2026-09-21, was "Global & Local penuh") | T3.7a (derivation, v1) + Premium gating (Fase 4, no task yet) | **Deferred with Premium** — not a Must-have v1 AC. T3.7a verifies the league derivation itself (band boundaries, equals leaderboard points, resets per season); the Freemium/Premium *gating* has no owning task until the Premium tier is scheduled |
| 4.5.5 | Leaderboard visibility gated on granted location permission, not region (added 2026-09-22, replaces region-based access — product-spec.md §4.1 D1 reversal) | Task C of the Local Leaderboard/region reversal (`6a4cfb4`) | **DONE 2026-09-23** — `LocationAuthorizationObserver` + `LeaderboardLockedView` shipped, merged to `main` (`99cd7ef`), CI green (iOS 187/187 incl. new `LocationAuthorizationObserverTests.swift` closing a coverage gap found in merge review). Permission-denied fallback (locked Leaderboard tab + Settings CTA) implemented per the PM's stated assumption in product-spec.md §4.5; still not confirmed in detail by the PM, just built as flagged |
| 4.6.1 | ~~Filter by kecamatan/kabupaten-kota/provinsi~~ | ~~T3.4, T3.5~~ *(phase-4-backlog.md, cancelled)* | **CANCELLED PERMANENTLY 2026-09-22** (PM sign-off, reverses the 2026-09-21 "Deferred" status) — scope too broad for the leaderboard logic needed; not a Must-have v1 AC, will never be one. AC struck through in product-spec.md §4.6, kept for historical record (was "Deferred", originally "Yes") |
| 4.6.2 | ~~"Belum cukup data" message for low-density regions~~ | ~~T3.3, T3.5~~ *(phase-4-backlog.md, cancelled)* | **CANCELLED PERMANENTLY 2026-09-22** — same as 4.6.1 (was "Deferred", originally "Yes") |
| 4.6.3 | ~~Region from profile, not per-run GPS (anti leaderboard-shopping)~~ | ~~T3.2, T3.5~~ *(phase-4-backlog.md, cancelled)* | **CANCELLED PERMANENTLY 2026-09-22** — same as 4.6.1 (was "Deferred", originally Partial) |
| 4.7.1 | Rank resets on season transition; lifetime stats don't | T3.7 | Yes |
| 4.7.2 | Time remaining in active season visible | T3.9 | Yes |
| 4.7.3 | Final season rank retained, viewable after season ends | T3.8 | Yes |
| 4.8.1 | Live map shows current position during tracking | T1.8 | Yes |
| 4.8.2 | Live polyline updates from `gpsRoute` as points arrive | T1.8 | Yes |
| 4.8.3 | No new GPS polling/subscription introduced for the map | T1.8 | Yes |
| 4.9.1 | Static route map shown on Run Summary | T1.9 | Yes |
| 4.9.2 | Static route map shown per run in Run History | T1.9 | Yes |
| 4.9.3 | Clear empty state for a run with zero GPS points | T1.9 | Yes |
| 4.10.1 | Per-km splits list with pace | T1.10 | Yes |
| 4.10.2 | Partial final split clearly marked, not rounded/hidden | T1.10 | Yes |
| 4.10.3 | Sum of split distances equals total run distance | T1.10 | Yes |
| 4.11.1 | ~~Sustained no-movement auto-transitions to Pause (time-based, not fix-reactive)~~ | T1.11 | **Removed 2026-09-22** — feature cut (PM sign-off), not deferred; was Yes. See product-spec.md §4.11 |
| 4.11.2 | ~~Auto-pause visibly distinct from manual pause in UI~~ | T1.11 | **Removed 2026-09-22** — same as 4.11.1 |
| 4.11.3 | ~~Resume from auto-pause behaves like resume from manual pause (auto-resume out of scope)~~ | T1.11 | **Removed 2026-09-22** — same as 4.11.1 |
| 4.11.4 | ~~Auto-paused time excluded from duration/pace like manual pause~~ | T1.11 | **Removed 2026-09-22** — same as 4.11.1 |
| 4.12.1 | Total elevation gain/loss shown on Run Summary | T1.12 | Yes |
| 4.12.2 | Altitude noise doesn't materially inflate gain/loss on a flat route | T1.12 | Yes |
| 4.13.1 | Audio announces distance+pace once per km crossed | T1.13 | Yes |
| 4.13.2 | User can disable audio cues entirely | T1.13 | Yes |
| 4.13.3 | No duplicate announcement from GPS jitter at a km boundary | T1.13 | Yes |
| 4.14.1 | Unfinished run from a prior session offers resume/save-as-finished on launch | T1.14 | Yes |
| 4.14.2 | Save-as-finished closes the run at its last persisted state (not "discard" — 2026-09-13 decision) | T1.14 | Yes |
| 4.14.3 | Resume continues from previously-saved state, not from zero | T1.14 | Yes |
| 4.15.1 | Always/While Using/Denied handled as 3 distinct states | T1.15 | Yes |
| 4.15.2 | While Using explicitly warns about background tracking limits | T1.15 | Yes |
| 4.15.3 | In-app Settings deep link to upgrade permission | T1.15 | Yes |
| 4.16.1 | Notification permission requested with contextual framing | T1.16 | Yes |
| 4.16.2 | Reminder fires only when no run today and streak at risk | T1.16 | Yes |
| 4.16.3 | No reminder if already ran today or permission denied | T1.16 | Yes |
| 4.17.1 | User can initiate account deletion from within the app | T2.22 | Yes |
| 4.17.2 | Explicit confirmation required before deletion executes | T2.22 | Yes |
| 4.17.3 | Personal data deleted/anonymized without violating ledger append-only invariant | T2.22 | Yes |
| 4.17.4 | Verified end-to-end before App Store submission (release blocker) | T2.22 | Yes |
| 4.18.1 | All local runs appear in the list, most recent first | T1.5 | Yes |
| 4.18.2 | Displayed values match what's stored in Core Data for each run | T1.5 | Yes |

**4 `Partial` rows remain** (4.1.1, 4.2.1, 4.3.2, 4.4.2) — was 5 until
2026-09-21, when 4.6.3 left the count with the rest of AC 4.6.x (Local
Leaderboard deferred to Fase 4, so those three rows became `Deferred`, not
`Partial`; **updated 2026-09-22: now `CANCELLED PERMANENTLY`, not
`Deferred`** — see the rows themselves; 4.5.4 is likewise `Deferred with
Premium`, unaffected by this change). None
block the reconciliation feature (4.3.2's Partial is a narrower,
separate gap — `trust_multiplier` exposure — left after the
reconciliation redesign closed the flagged/approved/rejected half of
that AC). Tracked here, not fixed in this pass, so they don't repeat the
pattern of silently surviving future rounds unnoticed. **31 new rows**
(AC 4.8-4.17, product-spec.md's 9 Fase-1 + 1 Fase-2 gap
additions) — all owning tasks (T1.8-T1.16, T2.22) were written with a DoD
item per AC from the start, so none begin life as `Partial`. **Plus 2
more rows (4.18.1-4.18.2, added 2026-09-13)** — Run History (T1.5) was
promoted from Should to Must-have (Round 7 finding N7-4, resolved) since
§4.9 AC2 load-bears on it; T1.5's existing DoD already verifies both,
carried over unchanged. This is a
deliberate application of the lesson the original 4 audit rounds taught
(spec → task traceability must exist from day one, not be retrofitted).

## Testing Strategy — what runs when, and when a phase is "tested enough"

Added 2026-09-17. Nothing here is a new testing requirement: every layer
below already existed, specified inside individual tasks. The problem this
section solves is that they were spread across five gate tasks in three
files, so "when does integration testing happen?" and "when is testing
enough to close this phase?" had no single answer a builder could look up.

### The five layers

| Layer | What it covers | Where it lives | When it runs |
|---|---|---|---|
| **1. Unit** | Pure logic — point formula, level derivation, streak, splits, elevation, anti-cheat rules | `LajuTests/` (XCTest), `backend/` (vitest/jest) — repo-coding-rules.md §4 | Every task, before its own DoD can be checked. Never deferred |
| **2. Fixture parity** | Client and server `calculatePoints` agree | `shared/point-formula.fixtures.json`, read by both suites (ADR-0007) | T1.1 writes it; T2.6 must pass it. Re-run on any formula change |
| **3. Integration** | Real pipeline, not mocks — component boundaries inside one side | T2.13 (anti-cheat against the real `POST /api/runs` pipeline), T2.12d (idempotency), T2.12e (p95 load), T3.10 (season close/open with seeded multi-user data) | At each phase's gate task, before sign-off |
| **4. Device (manual)** | Anything needing real GPS movement, real battery, real backgrounding | [deferred-manual-tests.md](../../04-quality-security/deferred-manual-tests.md) | Batched into one session per phase — see sequencing below |
| **5. Phase gate** | Go/no-go on the phase as a whole | T0.9, T1.17, T2.13→T2.21, T3.10 | Last task of each phase. A phase is not closed until its gate signs off |

Layers 1-3 are automated and belong in CI (T0.10 wires the pipeline;
T2.13's DoD explicitly requires its suite be "part of the CI pipeline, not
a one-off manual run"). Layer 4 is the only manual one, and it is the only
layer allowed to be deferred — which is exactly why it has its own tracker
file rather than living as scattered unchecked boxes.

### Why device tests are batched, not run per-task

A test needing 20 minutes of real outdoor movement cannot be run each time
a task lands without stalling every task behind it. So a DoD item of that
kind gets a row in `deferred-manual-tests.md` *the moment it is written*,
the task proceeds as **PARTIAL**, and all such rows are executed together
in one session before the phase gate. The row moves to `[x]` in its own
task file only after it actually passes — `deferred-manual-tests.md` tracks
what is outstanding, never what was already done.

**A phase gate cannot sign off while its phase has open rows in that file.**
That is the rule that makes "PARTIAL is fine for now" safe rather than a
way for tests to quietly never happen.

> **How this rule is enforced (2026-09-17).** It was briefly a convention
> this file asserted with nothing checking it — the gate tasks had no DoD
> item for it, and for Fase 2 and 3 nothing else covered it either. For
> Fase 1 it was only loosely masked, because T1.8's and T1.13's rows
> overlap T1.17's "every Fase-1 feature exercised at least once" item —
> but a battery *re-measurement* and a *screen-locked* audio check are not
> implied by "exercised".
> **Closed 2026-09-17.** The three **phase-wide** gates — T1.17 (Fase 1),
> T2.21 (Fase 2), T3.10 (Fase 3) — now each carry an explicit DoD item
> requiring that every row in `deferred-manual-tests.md` belonging to
> their phase is either Pass or documented as an accepted limitation (the
> pattern T0.9's battery item set). T1.17's version names T1.8's battery
> re-measurement and T1.13's screen-locked audio check specifically, since
> neither is implied by its existing "exercised at least once" item.
>
> **T2.13 deliberately does not carry it.** It is a narrow anti-cheat
> verification gate, not a phase-wide one; T2.21 is Fase 2's release gate
> and owns the sweep. Putting it on both would let an unrelated row — such
> as T2.0a's tab-bar rendering check — block anti-cheat sign-off, which is
> not what the rule is for. A phase gate also never gets its own row in
> that file, since a gate listing itself can never be satisfied.

### Fase 1 exit sequence (current phase)

Concrete ordering, because this is the phase actually in progress:

1. T1.1-T1.6, T1.9-T1.12, T1.14-T1.16 — **closed**, all DoD items checked. Note that "closed" does not mean every one was fully device-verified: T1.12, T1.15, and T1.16 each carry a note in their own DoD text that a real on-device pass is still desirable (elevation on a real hilly run, the permission banner rendering, the reminder firing after real elapsed time). Those notes were judged non-blocking when the items were checked; the T1.17 dogfood sessions are the natural place to confirm them. **T1.11 (within that range) was subsequently REMOVED 2026-09-22** (PM sign-off, feature cut) — it was genuinely closed/verified before removal, but no longer needs T1.17 dogfood exercise since the feature no longer exists; see product-spec.md §4.11.
2. T1.8 and T1.13 — code complete, one deferred device row each.
3. **One dogfood session block** covering all three remaining items at once:
   start a run screen-on with the map visible (closes T1.8's battery row),
   then lock the screen and continue past two km boundaries (closes
   T1.13's audio row), and repeat across ≥3 distinct days for ≥5 runs
   total (closes T1.17's own four DoD items).
4. T1.17 sign-off recorded → **Fase 1 closed**, Fase 2 (T2.1) starts.

Nothing in Fase 2 depends on Fase 1's device tests, so T2.1-T2.2
(provisioning and schema migration) may be started in parallel with the
dogfood sessions if desired — they touch no iOS code. Everything from
T2.3 onward assumes Fase 1 is closed.

### What "tested enough" means per phase

- **Fase 0** — closed. T0.9 gate passed: background survival ~59min, 3%/hour battery, force-kill integrity.
- **Fase 1** — closed when T1.17's four DoD items pass and zero Fase-1 rows remain open in `deferred-manual-tests.md`.
- **Fase 2** — two independent gates, both required: T2.13 (anti-cheat demonstrably working, in CI) and T2.21 (release gate — also verifies offline sync, progress screen, and the reconciliation branch). T2.22 account deletion is tracked separately under pre-launch-checklist.md §4 as an App Store gate, not folded into either.
- **Fase 3** — Season only (Local Leaderboard cancelled permanently 2026-09-22, not deferred — was "deferred to Fase 4" as of 2026-09-21). Closed when T3.10's full season close→open cycle passes with seeded multi-user data on the global leaderboard.
- **Pre-submission** — `pre-launch-checklist.md` is a separate track from phase gates. It gates App Store submission, not phase completion, and includes items (Privacy Policy, App Privacy label) that no task owns because they are not code.

Open findings from [security-review.md](../../04-quality-security/security-review.md)
and [code-quality-audit.md](../../04-quality-security/code-quality-audit.md)
are **not** phase gates and do not block the sequence above. They are
tracked in their own registers. All of both registers' original Blockers
are now resolved: SEC-9 (rate limiting) by T2.20a, 2026-09-21; SEC-1 (GPS
retention policy) by an explicit decision — indefinite retention — made
2026-09-22; and `code-quality-audit.md`'s CQ-2 (`RoutePointBuffer.flush`
could silently destroy a route) fixed and resolved 2026-09-22, verified via
real CI evidence (PR [#1](https://github.com/riporipo223/laju-app/pull/1),
191/191 tests passing, PR left open/unmerged for the user's own review).

## Fase 0 — Setup
- [x] T0.1 — Init repo scaffolding (monorepo: ios/ + backend/) (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.2 — Init native Xcode project (Swift + SwiftUI, iOS 16 min) — all DoD items verified: builds/runs on iOS Simulator (iPhone 17, iOS 26.3), iOS 16.0 deployment target, XCTest target running (2 tests passing), SPM configured, Strict Concurrency/warnings-as-errors enabled (and caught 2 real bugs) (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.3 — Configure SwiftLint/SwiftFormat across the iOS app — 0 violations, both tools installed & config verified clean (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.4 — iOS build running on physical device — verified on iPhone 13 (iOS 18.6.2), team `NTHHTF27HU`, bundle id `com.designbyripo.laju` (moved off `com.laju.app` — globally collided with a different Apple Developer account); steps + blockers documented in `ios/README.md` (lihat [phase-0-setup.md](./phase-0-setup.md))
- ~~T0.5 — Android dev-client build~~ — removed, Android postponed with no timeline (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.6 — Set up local Core Data schema for runs (data/sync layer skeleton) — all DoD items verified via `PersistenceTests` (XCTest, passing) + real on-device data (13 Run rows inspected directly in the on-device SQLite store). Real bug found + fixed along the way: `NSPersistentContainer(name:)` re-parsing the model per-instance caused a Core Data entity-ambiguity error when 2 `PersistenceController`s existed in one process — fixed by caching the parsed model (see `PersistenceController.swift`) (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.7 — Integrate CLLocationManager (permissions, background config) — all 3 DoD items verified on device: permission-prompt flow, background delivery (~59min), and console logging (4 real GPS points captured live via `devicectl --console` over ~2min) (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.8 — Basic start/stop run UI persisting raw GPS trail to Core Data — all 3 DoD items verified on device: non-empty GPS trail, incremental saves proven mid-run against SQLite, and distance accuracy cross-validated against Strava (660.90m vs 660m, ~0.15% deviation) with a clean point-by-point raw-data check (50/50 pairs under speed threshold, no hidden jump-then-correction) (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.9 — Verify background tracking survival + battery benchmark (phase DoD gate) — all 4 DoD items PASSED on physical device (iPhone 13, iOS 18.6.2): background survival (~59min), GPS capture pipeline, force-kill data integrity, and battery drain (clean retest: 49%→46% over 60min = 3%/hour, unplugged/locked/idle, under the <5%/hour target — supersedes the earlier contaminated 25%/hour datapoint). A second real bug surfaced during this same battery retest — a stationary phone indoors accumulated 34.9m of phantom distance over the 60min window despite never moving; root cause was the per-step jitter floor from the previous fix only guarding against one big jump, not a reference point slowly drifting one small "plausible" step at a time. Fixed with a stationary anchor (`RunViewModel.swift`) — **RESOLVED**: retest confirmed 0m distance over a continuous 61.8min stationary session (well past the ≥35min bar), though the anchor radius-check itself wasn't directly exercised (only 1 GPS point arrived all session — a strong practical result, not a direct proof of the anchor mechanism; documented as a known limitation, see tech-spec.md §2.1b). See phase-0-setup.md T0.9 for full detail (lihat [phase-0-setup.md](./phase-0-setup.md))
- [x] T0.10 — CI: path-filtered lint/format/test pipeline (ios/ + backend/) — verified green on GitHub Actions, split into `ci-ios.yml`/`ci-backend.yml` with real `paths:` triggers (not just `if: false`) so `ios/**` and `backend/**` changes genuinely trigger independently — confirmed both directions: an `ios/**` change triggered and passed CI (iOS) (run [34678173791](https://github.com/riporipo223/laju-app/actions/runs/34678173791)), and a change touching neither path triggered nothing. Two real bugs found + fixed getting here: (1) the workflow hardcoded `-destination 'platform=iOS Simulator,name=iPhone 16'`, which isn't a provisioned simulator on the `macos-15` runner image — fixed by discovering an available iPhone simulator's UDID dynamically via `xcrun simctl`; (2) the original single-workflow design only had `if: false` disabling the backend job, not real path filtering — split into two workflow files to match repo-coding-rules.md's actual design intent (lihat [phase-0-setup.md](./phase-0-setup.md))

## Fase 1 — Core Loop Offline
- [x] T1.1 — Implement calculatePoints in ios/Laju/PointFormula with XCTest — all DoD items verified: constants/brackets match tech-spec.md §2.3 exactly, 13-row fixture covering every bracket boundary + streak 0/1/7/8 + zero-distance, all 6 tests passing on simulator (2 PersistenceTests + 4 PointFormulaTests) (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.2 — Post-run summary screen wired to point-formula (offline estimate) — all 3 DoD items verified via `RunViewModelTests.swift`; visually confirmed on physical device (2026-09-12 re-verify) — Run Summary sheet appeared immediately on Stop showing distance/duration/pace/estimated points (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.2b — Pause/resume run tracking — all 4 DoD items verified via `RunViewModelTests.swift`; visually confirmed on physical device (2026-09-12), which also surfaced and fixed a second real anchor-drift bug (poor-accuracy first fix seeding a false 35m stationary drift) — see tech-spec.md §2.1b and `testPoorAccuracyFirstFixDoesNotSeedFalseAnchorDrift`; retested with the same device scenario, `distanceMeters` confirmed 0m via `devicectl device copy from` pull of the on-device Core Data store, not just the UI (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.3 — Local level progression from cumulative points — all 3 DoD items verified: `levelThresholds` matches database-api-spec.md §1 exactly (row-for-row `Equatable` test), level/pointsToNextLevel derivation checked at every boundary, level-up detection wired into `RunViewModel.stop()` with a basic visual indicator in `RunSummaryView` (18/18 tests passing); visually confirmed on physical device (2026-09-12 re-verify) (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.4 — Local streak tracking feeding streak_bonus (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.5 — Local run history screen — Must-have (promoted from Should 2026-09-13, Round 7 finding N7-4); both DoD items verified on physical device — list shows real runs most-recent-first with correct data, empty state confirmed distinct (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.6 — Local profile/progress screen (offline) — both DoD items verified; built 2026-09-14 in the design-system pass (`ProfileView.swift`), level/progress derived via `LevelProgression` over summed `Run.estimatedPoints`, live-updating via `@FetchRequest` so no app restart is needed after a run (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [ ] T1.8 — Live map during tracking (MapKit) — **PARTIAL**, DoD 1-3/4 done, item 4 (battery re-measurement) DEFERRED to [deferred-manual-tests.md](../../04-quality-security/deferred-manual-tests.md) (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.9 — Static route map (Run Summary & History) — all 3 DoD items verified on physical device + on-device Core Data store (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.10 — Splits per kilometer (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] ~~T1.11 — Auto-pause (user-facing)~~ **REMOVED 2026-09-22** (PM sign-off, feature cut not deferred; code deleted, drift-guard GPS filtering it reused stays intact) (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.12 — Elevation gain/loss — both DoD items verified; `ElevationTracker.compute(points:)` called from `RunViewModel.stop()` and `RunRecovery.finalize`, noise-rejection proven against a synthetic noisy-flat fixture (`ElevationTrackerTests`), not only a real hilly route (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [ ] T1.13 — Audio cues — **PARTIAL**, DoD 3/4 done (once-per-km content, global disable toggle, jitter-dedupe inherited from `SplitTracker`); item 4 (screen-locked/backgrounded device verification) outstanding, tracked in [deferred-manual-tests.md](../../04-quality-security/deferred-manual-tests.md) (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.14 — Crash/interrupt recovery flow (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.15 — Refine location permission flow — all 3 DoD items verified; `LocationPermissionBanner.swift` gives Always/While-Using/Denied three distinct copies, the While-Using notice explicitly warns about background-tracking loss, and "Buka Pengaturan" deep-links via `UIApplication.openSettingsURLString` (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [x] T1.16 — Notification permission + streak reminder — all 5 DoD items verified; contextual prompt gated on `streakDays >= 1 && .notDetermined`, N-day-ahead scheduling so a reminder fires on days the app is never opened, per-date identifiers prevent duplicate stacking (`StreakReminderSchedulerTests`). A real bug was found and fixed here: a plain foreground before running wiped today's own reminder (`testForegroundBeforeRunningTodayStillHasTodaysReminderScheduled` is the regression test) (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))
- [ ] T1.17 — Internal dogfood QA pass (phase DoD gate) — renumbered from T1.7 (lihat [phase-1-core-loop-offline.md](./phase-1-core-loop-offline.md))

## Fase 2 — Backend + Sync + Global Leaderboard
- [ ] T2.0a — Navigation shell (`TabView` root, Track + You) — **PARTIAL**, code complete and verified on simulator; physical-device check outstanding (iOS 26.3 rendering artifact, not reproducible on the iOS 16 deployment target from this machine), tracked in [deferred-manual-tests.md](../../04-quality-security/deferred-manual-tests.md) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.1 — Provision Supabase project + Next.js backend skeleton on Vercel — both DoD items verified live: `GET /api/health` returns 200 from `https://backend-eight-gules-56.vercel.app`; Supabase project `laju` (ap-southeast-1) connected, credentials in Vercel env (anon=Config, service_role=Secret) and `.env.local` (gitignored), REST API confirmed reachable (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.2 — Migrate core DB schema (User, Run, PointTransaction, Season, LeaderboardEntry, LeaderboardScope) — all 6 DoD items verified live against the remote Supabase project via `psql`, including functional trigger tests (not just structural checks): the `Run.updated_at` trigger fires on `status` change and correctly does NOT fire on unrelated column changes; the `LeaderboardScope` `GLOBAL` sentinel was inserted and read back through the real composite PK (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.3 — Supabase Auth integration (mobile sign up/in + backend JWT verification) — **PARTIAL, narrower since 2026-09-21**: backend JWT middleware verified live; **Google sign-in verified end to end on the real button** (OAuth → session → authenticated sync/reconciliation/Profile/Ranks → force-quit, still signed in; Google added as a second provider that day, reversing "Apple only"); the **Apple** round-trip is still unverified because it needs the paid Apple Developer Program, tracked in [deferred-manual-tests.md](../../04-quality-security/deferred-manual-tests.md) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.4 — POST /api/profile/complete endpoint — **DONE 2026-09-21**: endpoint verified live earlier (201 create, 400 on missing region, upsert non-duplicating); the "onboarding calls this" item, blocked until now, is built and **verified live with a real session and no seeding** — a new onboarding step (username + 3 region fields, free text until T3.1's picker) creates the row, shown only when the server answers the new `profile_missing` 401 (`8002079`). Caveat: region is free text, so spelling varies until a catalog/picker exists (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.5 — POST /api/runs endpoint — ingestion only (no calc/anti-cheat yet) — all 5 DoD items verified live with a real Auth JWT: 201 create (row confirmed in Postgres, pace arithmetic checked), 401 unauthenticated, 409 no-region, 422 malformed route point, 400 zero distance (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.6 — Server-side point calculation module (fixture-parity with client formula) — all 3 DoD items verified: `backend/lib/point-calculation.ts` passes all 16 rows of `shared/point-formula.fixtures.json` via `it.each` (not hardcoded), empty-fixture guard present as its own test, constants match `PointFormula.swift` exactly (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.6b — Build GPS test fixture corpus (spoofed vs. real) — **PARTIAL**, 7 synthetic fixtures done and independently verified (Haversine, not the generator's own math); the ≥3-genuine-routes DoD item is blocked — zero on-device run data was ever exported to a file, and the connected device went unavailable mid-task. Not fabricated as a workaround; tracked in `backend/fixtures/gps-routes/README.md` and [documents/README.md](../../README.md) §3 (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.7 — Anti-cheat check: pace cap — both DoD items verified against T2.6b's real fixtures (not hand-rolled test data): breach fixture flags correctly, both clean controls (including the near-boundary 4:30/km one) produce zero false positives, no cross-trigger on the speed-jump fixture (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.8 — Anti-cheat check: GPS speed jump detection — all 3 DoD items verified against T2.6b's real fixtures, including that a single extreme spike (teleport.json) correctly does NOT trigger this check (belongs to T2.9 instead) and no status field is asserted (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.9 — Anti-cheat check: distance/duration sanity (teleport detection) — both DoD items verified against T2.6b's real fixtures; threshold (150km/h single-segment) is a documented starting value since tech-spec.md gives no explicit number for this check, unlike pace cap/speed jump (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.10 — Anti-cheat check: elevation anomaly signal — both DoD items verified against T2.6b's real fixture; architecturally distinct from T2.7-T2.9 (takes other checks' exclusions as input, never excludes a segment itself — proven always-empty `excludedSegmentIndices`, not just "usually doesn't trigger") (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.11 — Trust score model + trust_multiplier — all 9 DoD items verified: pure-formula unit tests for every rate/floor/ceiling/recovery rule, DB-query-level tests distinguishing `resolved_via='auto'` vs `'manual'` (a new nullable `run.resolved_via` column, added this task — nothing in the existing schema recorded resolution method), and a full live round-trip: real Auth JWT, 6 seeded `run` rows building a known 30-day-window history (incl. one deliberately 31 days old to prove window exclusion), a real submission through the deployed `POST /api/runs` returning `final_points_awarded: 9` = `round(10 × 0.89)`, and `user.trust_score` confirmed `0.91` via `psql` after recompute — all test data deleted after (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.12a — Wire anti-cheat pipeline + aggregate status resolution — all 3 DoD items verified: exact-percentage boundary unit tests (both inclusive lower bounds), status/confidence decision confirmed to live only in `status-resolution.ts` (T2.7-T2.10 unchanged), thresholds as exported config constants; plus a full live round-trip — 4 real GPS routes engineered to land on exactly 0%/10%/30%/50% excluded, submitted through the deployed `POST /api/runs`, each resolving to the correct `validated`/`flagged+low`/`flagged+high`/`rejected` — all test data deleted after (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.17 — GET /api/seasons/active endpoint + seed initial season — both DoD items closed (2nd item closed 2026-09-18 once T2.12c landed and proved the season_id linkage live) — endpoint verified live (401 unauthenticated, 200 with real JWT matching database-api-spec.md §2.5's shape, `days_remaining` confirmed dynamically computed); one Season row seeded via migration and confirmed via `psql` (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.12c — PointTransaction ledger write + User aggregate + season linkage — all 5 DoD items verified live: response shapes match database-api-spec.md §2.2 for validated/flagged/rejected; zero PointTransaction rows for a rejected run (unit test + live 0-count); all written rows reference the real seeded season_id; `resolved_at` correct per status; `User.total_points` recomputed as the ledger's own SUM (not incremented) across 3 real runs, matching exactly (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.12d — Duplicate submission idempotency — both DoD items verified: sequential duplicate returns the existing result (unit test + live, exactly 1 run/1 PointTransaction after 2 identical submissions); the DB unique constraint (`run_user_id_started_at_key`) is the real race backstop, proved with two genuinely concurrent raw `psql` inserts (one wins, one fails with error 23505 — not just HTTP timing) and a unit test confirming the app catches that exact error and returns the winner's result instead of a 500 (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.12e (ACCEPTED LIMITATION 2026-09-19, pending re-test after Supabase Pro: p95 3,827 ms at 100 concurrent, ≈25 submissions/s ceiling, likely Free-tier compute not code; not being optimized now) — Load test / p95 latency verification — **FAILS the budget, documented not fixed (this task's own scope).** Measured live: 100 concurrent `POST /api/runs`, p95=7801ms vs the 1.5s target (~5.2× over); an isolated single-request baseline was already 4757ms, pointing at the pipeline's ~9 sequential Supabase round-trips per request (not concurrency contention) as the root cause. Routed back to T2.12a/T2.12c for optimization per this task's own DoD note — a real blocker for T2.21's release gate until addressed (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.12b — Anti-cheat resolution & auto-approve/reject lifecycle (confidence-based) — all 6 DoD items verified live against the real production DB: LOW auto-resolves after 48h, HIGH stays flagged indefinitely (confirmed untouched across 3 other resolve operations), manual-reject writes a correct compensating `PointTransaction` (original untouched, net-zero), manual-approve on HIGH writes none, and `trust_score` recomputation confirmed correct for all 3 outcomes (auto-approve removes decay, manual reject/approve keep it). Manual-override runbook + CLI script documented, no admin UI built (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.12f — Register resolve-flagged-runs as Vercel Cron job — all 3 DoD items verified live: `vercel crons ls` confirms real registration, the deployed route (secret-gated, confirmed 401/401/200) resolved a real seeded 50h-old LOW run while leaving a real 200h-old HIGH run completely untouched. **Note:** schedule is daily (`0 0 * * *`), not the originally-scoped ≤12h — Vercel Hobby plan hard-rejects sub-daily cron (confirmed live via a real rejected deploy attempt); user chose daily over a Pro upgrade, tracked as an open item in documents/README.md (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.13 — Anti-cheat verification pass (synthetic bad-data test suite) — gate task — **signed off 2026-09-18.** All 5 DoD items verified: 2 new integration test files (no mocks, real Supabase) prove all 4 anti-cheat checks + negative controls through the real `POST /api/runs` pipeline, and the LOW/HIGH/manual resolution lifecycle through the real DB functions T2.12f's Cron route and the manual-override runbook both call. Confirmed genuinely running (not skipped) in a real GitHub Actions run (19/19 files, 122/122 tests passed) after fixing a pre-existing eslint FlatCompat crash that predates this session and adding 3 Supabase credentials as GitHub repo secrets. Zero stray test data left in Postgres or Supabase Auth afterward (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.14 — Mobile sync queue (offline → online push, retry, initial status apply) — all 4 DoD items verified: new `SyncService`/`APIClient` (Services/Networking, Services/Sync) push offline runs to `POST /api/runs`, retry on failure without dropping the run, and populate `serverRunId`/`serverStatus`/`flagConfidence`/`finalPointsAwarded`/`anomalyFlags`/`resolvedAt` from the response — verified specifically for a `flagged` response. 8 new XCTest tests (real `SyncService`, stubbed network, fake connectivity monitor), full iOS suite 97/97 passing, app confirmed to boot cleanly in Simulator with the real `NWPathMonitorAdapter` wired in. Full real-device airplane-mode transition tracked in deferred-manual-tests.md. **Bonus:** fixed 3 unrelated pre-existing issues blocking `ci-ios.yml`, which had never once passed since being added — `ci-ios.yml` is now genuinely green for the first time, confirmed via a real GitHub Actions run (97/97 tests) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md)) **2026-09-21 — first real-app upload found a defect the stubbed tests hid:** the client's fractional `durationSeconds` made `POST /api/runs` fail with a `500` on the integer column, so no real run could ever sync; fixed server-side (`d973ce0`) and confirmed end to end in the Simulator (run synced, `serverRunId` matches) — see "Real client–server chain" in the phase file
- [x] T2.14c — GET /api/runs status reconciliation endpoint — all 6 DoD items verified live: deployed to `https://backend-eight-gules-56.vercel.app`, `400`/`401` cases confirmed via real curl, pagination draining and cross-user isolation verified against real Supabase data (201 seeded rows, two genuine Auth users), `EXPLAIN ANALYZE` on the production query (5000 rows) shows a 0.135ms Index Scan on `run_user_id_updated_at_idx`, well under the 300ms NFR (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.15 — GET /api/users/me/progress endpoint — all 3 DoD items verified live: deployed to `https://backend-eight-gules-56.vercel.app`, response shape matches database-api-spec.md §2.3, `total_points` verified equal to an independently re-summed real `PointTransaction` ledger (not just the aggregate column), `levelThresholds` match the spec table row-for-row (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.16 — Update mobile profile/progress screen to use server data — all 3 DoD items closed: new `ProgressViewModel` (T1.6 never built one; logic was inline in `ProfileView`) fetches `GET /api/users/me/progress`, `refresh()` callable externally (verified directly), offline falls back to local estimate (confirmed in Simulator). iOS 104/104. **Server branch seen live 2026-09-21** (Profile showed the server's 1 point vs ≈5 local) via a real Supabase session in the Simulator; Sign in with Apple itself still unverified (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.14d — Client status reconciliation loop — all 8 DoD items verified by 12 XCTest tests (iOS 116/116); found and fixed 2 real-server issues (PostgREST microsecond timestamps, nullable `final_points_awarded`) by hitting the live endpoint. **Verified against the real server 2026-09-21** with a real Supabase session in the Simulator (arranged flagged state, real override tool, app reconciled by itself) — see the phase file; Sign in with Apple itself still unverified (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.14b — all 3 DoD items verified (RunStatusCopyTests 8 tests, iOS 124/124, plus seen in Simulator with seeded runs); known UX gap: rejected rows still show the local estimate points — Surface anomaly reason & resolution status to user (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.18 — all 6 DoD items verified; scheduled via pg_cron (user-approved deviation from "Vercel Cron", Hobby plan is daily-only), one atomic SQL function; observed a real cron execution; 389 ms at 5000 users — LeaderboardEntry precompute job (global scope) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.19 — all 3 DoD items verified live (p95 204 ms after pinning Vercel to sin1; trust cutoff 0.5 applied in the precompute) — GET /api/leaderboard endpoint (global scope) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.20 — both DoD items verified (iOS 134/134; real view rendered and inspected; **seen with real server data 2026-09-21** (Ranks showed the user's row from the real endpoint, via a real Supabase session in the Simulator); Sign in with Apple itself still unverified) — Global leaderboard screen on mobile (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [x] T2.20a — API rate limiting (SEC-9 Blocker + SEC-10) — **DONE 2026-09-21** (`6bea1a8`): Postgres-backed per-user + per-IP limiter (atomic under concurrency: exactly 10 of 40; live: exactly 120 of 130 per IP, 30 of 35 per user), 429 + Retry-After, payload cap 413, client stops the batch on 429; backend 219/219, iOS 159/159, release gate 7/7 (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.21 (evaluated 2026-09-19: NOT passed — 3/7 items met at evaluation; SEC-9 item met 2026-09-21 → 4/8, 4 open: real-device sync/progress e2e, real-device visible-reason e2e, 3 outstanding Fase-2 deferred manual tests, sign-off; see phase file) — Phase gate: confirm anti-cheat verified before enabling public global leaderboard (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))
- [ ] T2.22 (PARTIAL 2026-09-19: 6/8 DoD verified live incl. field-by-field deletion and a fixed profile/complete revive hole; open: real-device local-wipe + fresh sign-up, and e2e before submission; new open item: Sign in with Apple token revocation) — Account deletion (App Store submission blocker) (lihat [phase-2-backend-sync-global-leaderboard.md](./phase-2-backend-sync-global-leaderboard.md))

## Fase 3 — Season System
> Renamed 2026-09-21 (was "Local Leaderboard Granular + Season System"): Local Leaderboard cut from MVP v1 → T3.2–T3.5 deferred to Fase 4 below, IDs kept. Numbering gap T3.1 → T3.6 is deliberate. **Update 2026-09-22: T3.2–T3.5 CANCELLED PERMANENTLY**, not deferred — see phase-4-backlog.md.
- [x] T3.1 — Mobile onboarding UX blocking run-start until region is set — shipped `8002079` (2026-09-21), checklist closed out 2026-09-22 during the T3.10 gate. **Superseded 2026-09-22 (same day)**: D1 reversed, region removed entirely. **Rework DONE 2026-09-23**: region step removed from onboarding, Leaderboard visibility now gated on location permission instead (Task C, `6a4cfb4`, merged `99cd7ef`); `region_*` columns physically dropped from production (Task B's migration, applied and verified live) (lihat [phase-3-season.md](./phase-3-season.md))
- [x] T3.6 — Season lifecycle management (upcoming → active → ended) — **DONE 2026-09-21** (`c0de85f`): one-active invariant enforced by a unique index, atomic `transition_season` with rollover, hourly `advance_seasons` that never leaves zero active seasons (overdue with no successor = `overrun`, stays active), CLI for the admin path; 12 real-database tests. **Ops note: Season 1 ends 2026-11-30 and no successor exists — create Season 2 before then** (lihat [phase-3-season.md](./phase-3-season.md))
- [x] T3.7 — Season-scoped rank reset on transition — depends on T2.18 now, not T3.2 (lihat [phase-3-season.md](./phase-3-season.md))
- [x] T3.7a — Season League derivation (out-of-band, 2026-09-21; "tier" = Season League, tech-spec.md §2.5; depends on T2.12c, T2.18, T3.7) (lihat [phase-3-season.md](./phase-3-season.md))
- [x] T3.8 — Historical final rank retention after season ends — now also retains final league (lihat [phase-3-season.md](./phase-3-season.md))
- [x] T3.9 — Season info screen with countdown (lihat [phase-3-season.md](./phase-3-season.md))
- [x] T3.10 — End-to-end verification: season close/open cycle (phase DoD gate) — **DONE 2026-09-22**, Phase 3 signed off (lihat [phase-3-season.md](./phase-3-season.md))

## Fase 4 — Backlog (out of scope for now)
- [ ] T4.1 — ~~Circle / Clan~~ Club, renamed 2026-09-23, **display name changed to "Circle" 2026-09-26** (internal `club` unchanged) — scoped 2026-09-23 (§4.24 AC1-AC24, incl. Premium admin tools — T4.8 merged in; open points closed 2026-09-24 except delete-vs-archive, analytics period/N, challenge details), built after T4.15 (lihat [phase-4-backlog.md](./phase-4-backlog.md))
  - [x] T4.1a — extend `club` (description, privacy, invite code) — applied + verified live 2026-09-25 (1/3 checks, 2 blocked by session classifier — see phase-4-backlog.md)
  - [x] T4.1b — backend: create (free, Premium gate reverted 2026-09-26) + browse/join/leave/member list all built — `POST`/`GET /api/clubs`, `GET`/`DELETE /api/clubs/[id]/members`, `POST /api/clubs/[id]/join` — 12/12 create tests pass (TDD: failing test added first, proving free-tier creation was rejected, then the gate removed). Internal leaderboard is separate (T4.17). **Still open from the 2026-09-26 audit: owner-removes-member endpoint doesn't exist yet (§4.24 AC23, must ship free, not admin tooling); member cap (20 Free/100 Premium, AC22) not yet enforced; freeze policy at cap (AC24) not yet built**
  - [x] T4.1c — iOS UI — Create Club (Premium upsell gate removed 2026-09-26, `PremiumUpsellView.swift` deleted — no other caller) + `ClubBrowseView` + `ClubMemberListView` all built, wired into the Club tab (not "Club Saya" in You tab — moved per T4.2c's 2026-09-24 nav change) — BUILD SUCCEEDED, 234/234 tests pass. **Still open from the 2026-09-26 audit: display copy needs to say "Circle" everywhere (8 locations found, see HANDOFF.md "Audit drift 2026-09-26" item 6 — includes an open question on Club War's name); kick-member UI missing (blocked on the backend endpoint above)**
- [ ] T4.2 — Club War — confirmed to build 2026-09-23, mechanism finalized 2026-09-23 (§4.19 AC1-AC15); T4.2a/b/c pulled forward and built 2026-09-24 (`9b40c34`) ahead of the rest of Fase 4. **BUILD ON HOLD 2026-09-26 (not cancelled) — see product-spec.md §4.19's header note** (lihat [phase-4-backlog.md](./phase-4-backlog.md))
  - [x] T4.2a — data model (club, roster, club_war tables) — **APPLIED to production 2026-09-24**, verified: 5 tables exist, RLS enabled on all 5, max-3-clubs trigger, one-open-war trigger, and the one-club-per-user PK all genuinely rejected a real bad insert (begin/rollback, zero rows leaked). See the migration file's own APPLIED banner (`20260923200000_club_war_schema.sql`)
  - [ ] T4.2b — backend API (challenge, precompute, forfeit rules) — code built and tested (364/364 backend incl. integration tests against the real applied schema, `9b40c34`), but **deliberately inert**: `isPremiumClub()` (`backend/lib/club-war/premium.ts`) is a stub that always returns `false` until T4.20 ships — no Club War can actually be created by anyone yet, by design, not a bug
  - [ ] T4.2c — iOS UI (challenge, accept/decline, war status, record) — self-described "iOS scaffold" in `9b40c34`'s own commit message, iOS 193/193 passing; functionally blocked by the same T4.2b Premium stub above, so leaving unchecked rather than claiming done. **Location changed 2026-09-24**: moved from You tab to the new Club tab (§4.24 AC19 reversed same day — see product-spec.md)
- [ ] T4.3 — Matchmaking between clubs — confirmed 2026-09-23, suggestion-only; not scoped in detail (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.4 — Monetization: seasonal pass (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.5 — Monetization: advanced statistics — AC-complete 2026-09-24 (§4.25 AC1-AC5), confirmed kept as-is 2026-09-26 despite being a weaker hook than the rest of the bundle; Personal Record explicitly not merged with Achievement (T4.24-new) (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.6 — Monetization: exclusive badge — mechanism scoped 2026-09-26 (§4.31), content still pending PM's own list (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.7 — Monetization: premium profile — AC-complete 2026-09-24 (§4.26 AC1-AC5), **REVISED 2026-09-26: photo/bio now free for every tier, only alt icon stays Premium-only**; pricing $1.99/mo (was $7.99) (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- ~~T4.8 — B2B dashboard: running club~~ — **MERGED into T4.1, 2026-09-23**: club admin tools are part of Club, included in Premium; number retired (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.9 — ~~B2B dashboard: event organizer~~ ~~EO managed service~~ Laju Branded Events, concept replaced 2026-09-23 (lihat [phase-4-backlog.md](./phase-4-backlog.md))
  - [ ] T4.9a — `event` table (no region column)
  - [ ] T4.9b — staff-only tooling (CLI recommended) + read endpoint
  - [ ] T4.9c — iOS Events sub-tab in Ranks + external redirect (moves the location lock to the leaderboard sub-tab only)
- ~~T4.10 — Route map visualization (Mapbox)~~ — moved to Fase 1 (MapKit, T1.8/T1.9), no longer backlog (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.11 — Android support (postponed indefinitely) (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.12 — Redis-backed global leaderboard cache — AC-complete 2026-09-24 (§4.27 AC1-AC3); shares code with T4.17, do not run concurrently (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.13 — Native iOS platform integrations — AC-complete 2026-09-24 (§4.28 AC1-AC5), gated on T1.17 (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.14 — Companion smartwatch app — Apple Watch v1 shape finalized 2026-09-23 (§4.22 AC1-AC7) (lihat [phase-4-backlog.md](./phase-4-backlog.md))
  - [ ] T4.14a — Apple Watch v1: phone-side relay (WatchConnectivity)
  - [ ] T4.14b — Apple Watch v1: watchOS target + UI
  - [ ] T4.14c — Garmin companion — placeholder, not scoped
  - [ ] T4.14d — Huawei Watch companion — placeholder, not scoped
- [ ] T4.15 — Social Feed — built BEFORE Club (T4.1), decided 2026-09-23; v1 scope closed 2026-09-24 (public feed, delete-own-post moderation, validated/approved runs only). **Code-complete, migration VERIFIED LIVE 2026-09-25 (6/6 checks passed)**: migration applied (`20260924220000_social_feed_schema.sql`), backend routes + 32 unit tests pass, production endpoint confirmed live (401 not 500), iOS feed/composer compiled and tested on real Xcode toolchain (203/203 tests pass) — no outstanding verification gaps — see phase-4-backlog.md for the full breakdown. **Extended 2026-09-26 by new task T4.26** (Feed/Friends segments, follow, achievement-unlock post, caption) — see §4.33 (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.16 — Comment on social feed posts. **Built 2026-09-25**: migration applied + verified (3/5 checks), backend 13/13 tests, iOS 224/224 tests, BUILD SUCCEEDED. Flat comments, delete-own-only, no moderation (v1 scope) — see phase-4-backlog.md for the full breakdown (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.21 — Save Activity flow (Finish → Save Activity → publish, gear/map type/visibility). Added 2026-09-25. **Backend + iOS built, migration applied + verified live 2026-09-25 (4/5 checks — 1:1 constraint test blocked by session classifier, not claimed passed).** Backend 49/49 tests, iOS 214/214 tests, BUILD SUCCEEDED. 3D Map View and Friends Only visibility deferred (T4.20b/friend-graph not ready) — see phase-4-backlog.md for the full breakdown (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.17 — Club Global Leaderboard, added 2026-09-23, confirmed to build — §4.20 AC1-AC12, Season 1 = no reset. **Open question raised 2026-09-26, NOT resolved: still worth building given T4.1's internal Circle leaderboard turned out to be a cheap reuse — do not build until the PM answers explicitly** (lihat [phase-4-backlog.md](./phase-4-backlog.md))
  - [ ] T4.17a — precompute tables for both sections
  - [ ] T4.17b — two precompute jobs + read endpoint
  - [ ] T4.17c — iOS two-section screen
- [ ] T4.18 — User Season 91→60 days, forward-only from Season 2 — decided 2026-09-23; implementation scoped 2026-09-23 (Season 2 by hand via season.ts, overrun warning log, bands recalibrated after Season 2 data); not done (was missing from this list; added 2026-09-23) (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.20 — Premium subscription infrastructure — decided 2026-09-23 (§4.23 AC1-AC14), **pricing revised 2026-09-26 to $1.99/mo (was $7.99), still monthly-only/no annual/no trial**; T4.20b/c blocked by Apple Developer Program (verified); T4.20a unblocked (user_id non-null FK, decided 2026-09-23) and buildable before enrollment; T4.2b, §4.5 AC4, and T4.4–T4.7 depend on it, but **not unblocked by T4.20a alone** — see T4.20a's own line (lihat [phase-4-backlog.md](./phase-4-backlog.md))
  - [ ] T4.20a — `subscription` table (append-only) + RLS — **written 2026-09-24**
    (`20260924210000_add_subscription_table.sql`), verified via a real begin/rollback
    dry-run against production: table + both indexes + RLS created cleanly, `status`
    CHECK genuinely rejected an invalid value, `environment` CHECK genuinely rejected
    an invalid value, two rows for the same `original_transaction_id` with different
    `status` inserted cleanly (append-only pattern confirmed), then rolled back —
    zero trace left. **Deliberately NOT applied to production yet**, same two-step
    gate as T4.2a (write inert → review → apply as a separate decision). **Does not
    by itself unblock T4.2b/§4.5 AC4/T4.4–T4.7** even once applied — those need
    T4.20b (the actual Apple verification/status-check logic), which stays blocked
    in full by the Apple Developer Program regardless of this table's existence.
    T4.20a is the necessary foundation, not a functional unblock.
  - [ ] T4.20b — backend: App Store Server API verification + status endpoint
  - [ ] T4.20c — iOS: StoreKit 2 purchase flow + Restore Purchases
- [ ] T4.22 — Real-time anti-cheat warning (Track), added 2026-09-26 — §4.29 AC1-AC5. **Blocked on CQ-11 (code-quality-audit.md) being fixed first** (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.23 — Trigger Start via Triple Back-Tap (Track), added 2026-09-26 — §4.30 AC1-AC3 (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.24 — Achievement System (mechanism only), added 2026-09-26 — §4.31 AC1-AC5. Content list not yet delivered by PM (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.25 — Kartu NFC: Auth Link & Physical Reward, added 2026-09-26 — §4.32 AC1-AC6 (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] T4.26 — Social Feed: Feed/Friends Segments & Follow, added 2026-09-26 — §4.33 AC1-AC6, extends T4.15 (lihat [phase-4-backlog.md](./phase-4-backlog.md))

### ~~Deferred from MVP v1~~ CANCELLED PERMANENTLY — Local Leaderboard (moved from Fase 3, 2026-09-21; cancelled 2026-09-22; IDs unchanged, full detail in phase-4-backlog.md)
- [ ] ~~T3.2 — Extend precompute job to per-scope aggregation (kecamatan/kabupaten_kota/provinsi)~~ **CANCELLED PERMANENTLY 2026-09-22** (PM sign-off, not deferred) (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] ~~T3.3 — Insufficient_data handling in precompute job~~ **CANCELLED PERMANENTLY 2026-09-22** (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] ~~T3.4 — Extend GET /api/leaderboard with scope filters~~ **CANCELLED PERMANENTLY 2026-09-22** (lihat [phase-4-backlog.md](./phase-4-backlog.md))
- [ ] ~~T3.5 — Local leaderboard screen with scope filter UI~~ **CANCELLED PERMANENTLY 2026-09-22** (lihat [phase-4-backlog.md](./phase-4-backlog.md))

