# Laju App — Deferred Manual Tests

Created 2026-09-13. Centralized tracker for DoD items that need a real
physical-device test (long duration, actual movement, specific
conditions like outdoor/battery) that isn't practical to run one at a
time as each task lands. Add a row here **the moment** a task's DoD
needs this kind of test — don't wait to collect them manually later.
When a full testing session happens, work this list top to bottom so
nothing gets missed.

A row moves from here to its task's own DoD checkbox (`[x]`) only after
it's actually run and passed — this file tracks what's outstanding, not
a permanent record of what was tested (that lives in the task files
themselves, same as every other DoD item in this repo).

| Test | Task | Why deferred | Test scenario | Pass condition |
|---|---|---|---|---|
| Battery draw with live map on screen | T1.8 (Live map during tracking) | Needs ~15-20min of actual movement with the screen on and the map continuously visible — different scenario from T0.9's own battery baseline (background, screen locked), so it can't reuse that data and needs its own real-world run | Start a run, keep the screen on and the map visible the whole time, walk/move continuously for ~15-20 minutes, record battery % at start and end | Extrapolated %/hour stays reasonably close to T0.9's 3%/hour background baseline — no gross regression from MapKit rendering. Exact acceptable delta not fixed yet; judge against T0.9's number, not an unrelated absolute |
| Audio cue fires with screen locked / app backgrounded | T1.13 (Audio cues) | Needs ≥1km of real outdoor movement with the screen actually locked — a simulator or foreground run cannot exercise the `audio` background mode, which is the exact thing at risk (without it, announcements stop silently the moment the screen locks). Added here 2026-09-17: it was an open DoD item on T1.13 that had never been tracked in this file, despite this file's own "add a row the moment a task needs it" rule | Start a run, lock the screen immediately, walk/run ≥2km continuously so at least two km boundaries are crossed, phone in a pocket, audio cues enabled (headphones or speaker) | An announcement is heard at each km boundary while the screen stays locked — both the km figure and the pace are spoken (product-spec §4.13 AC1). The *second* announcement is the real pass condition: it confirms cues keep working rather than firing once before the app is suspended |
| Sign in with Apple full round-trip (sign in, force-quit, relaunch, still signed in) — **the Google equivalent was verified 2026-09-21** (real button, force-quit, still signed in); only the Apple one remains | T2.3 (Supabase Auth integration) | **Blocked by an account decision, not by anything technical.** Apple requires a paid Apple Developer Program membership to provision the Sign in with Apple capability — confirmed live 2026-09-17: `xcodebuild` refuses with "Personal development teams... do not support the Sign In with Apple capability" for team `NTHHTF27HU` (a free Personal Team). All code compiles cleanly (simulator build succeeds, 89/89 tests pass) and the backend half is fully verified live. User is enrolling in the Developer Program separately | Once enrolled: rebuild for the physical device (`Ripo Gagah`) or a simulator signed into a real Apple ID, tap the Sign in with Apple button, complete the system flow, confirm the app advances past onboarding. Force-quit the app, relaunch, confirm no re-prompt (session restored from Keychain) | A session exists after relaunch without re-authenticating — `AuthService.isSignedIn == true` on cold launch, provable via a debug log or breakpoint on `authStateChanges` |
| Tab bar renders correctly on the deployment target | T2.0a (Navigation shell) | The simulator run (iPhone 17 Pro, iOS 26.3) showed the two tab icons additionally drawn in the status-bar area on the **You** tab — the one wrapped in a `NavigationStack`. The Track tab is clean. Only the iOS 26.3 runtime is installed on this machine, so it cannot be determined whether this is an iOS 26-specific rendering behavior or a real layout bug; the deployment target is iOS 16 and the project's physical test device runs iOS 18.6.2 | Launch on the iPhone 13 (iOS 18.6.2), complete onboarding, and switch between the Track and You tabs. Inspect the status-bar area on the You tab specifically | No duplicate tab icons appear anywhere outside the tab bar itself, on either tab. If the artifact **does** reproduce on iOS 18, this becomes a real bug and the `NavigationStack` placement in `RootTabView` needs revisiting; if it does not, record it as iOS 26-only and close the row |
| Offline→online sync over a real network transition | T2.14 (Mobile sync queue) | `SyncService`'s connectivity-triggered sync (DoD item 1) is fully unit-tested with a fake `PathMonitoring`/stubbed `URLSession` (`SyncServiceTests.swift`, 8/8 passing) — proving the logic — and the app was confirmed to boot cleanly with the real `NWPathMonitorAdapter` wired in (simulator smoke test, 2026-09-18). What's not yet exercised is a real `NWPathMonitor` transition (airplane mode toggle) against the real deployed backend end-to-end, which needs real device network control, same category as this file's other real-environment tests | Grant location permission, record a short run with the device in Airplane Mode the whole time, stop the run, confirm it saves locally with `syncStatus="pendingSync"`. Disable Airplane Mode. Watch (via a debug breakpoint/log on `SyncService.syncPendingRuns`, or the run's local state in a later screen) for the run to sync automatically without relaunching the app | Within a few seconds of connectivity returning, the run's local `syncStatus` becomes `"synced"` and `serverRunId`/`finalPointsAwarded` are populated — no manual foreground/relaunch needed to trigger it |

**Ordering note (added 2026-09-17):** run the T1.8 and T1.13 rows *inside*
the T1.17 dogfood sessions rather than as separate trips — both need real
outdoor movement, and T1.17 already requires several such runs. Sequence
within a single session: start with the screen unlocked and the map
visible (satisfies T1.8's battery row), then lock the screen and continue
past two km boundaries (satisfies T1.13's row). Both rows then move to
`[x]` in their own task files, and T1.17's gate can close.

**A phase gate never gets its own row here.** T1.17 briefly had one, added
and removed 2026-09-17: since each gate's DoD now requires every row for
its phase to Pass, a gate listing *itself* is a rule that can never be
satisfied. This file tracks individual deferred measurements; the gates
that sweep it live only in the task files.

---

**Format note:** every new row must fill all 5 columns — a vague "test
this later" entry defeats the point of this file. `Task` should be the
exact task ID (e.g. `T1.10`) so this file cross-references cleanly with
`tasks/README.md` and the relevant phase file. `Pass condition` should
be concrete enough that whoever runs the test later (possibly not the
person who wrote the row) can judge pass/fail without re-deriving intent
from scratch.
