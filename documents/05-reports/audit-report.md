# Laju App — Pre-Execution Audit Report (Round 7 — 9 Fase-1 + 1 Fase-2 gap additions)

Scope: all files in `Laju/documents/` after adding 9 previously-missing
Fase-1 features (product-spec.md §4.8-§4.16 — live map, static map,
splits, auto-pause, elevation, audio cues, crash recovery, permission-flow
refinement, streak reminder) and 1 Fase-2 addition (§4.17 account
deletion, App Store Guideline 5.1.1(v)), plus a new `pre-launch-checklist.md`.
Two independent audits run in parallel (`ecc:architect` — system
design/consistency, `ecc:planner` — task-graph/dependency/traceability),
findings merged below, same methodology as Round 6. **All 18 Blockers
found were fixed in this pass** (14 from `ecc:architect`, 4 from
`ecc:planner`, with real overlap between them). Most Notes were also
fixed opportunistically since the same files were already open; the
remaining 2 needed a product decision rather than an editorial call —
both were raised, decided, and resolved on 2026-09-13 (see Part 3).

**Verdict: Fase 1/2 documentation — CLEAN, genuinely closed, for the 9+1
gap additions.** The pre-existing Fase 0/1 corpus (Round 6's scope) was
not re-audited from scratch this round — only the new additions and what
they touch were in scope. **Zero open Blockers or Notes remain from
Round 7** — ready for execution to proceed (starting at the next
un-`[x]`ed task, T1.8).

---

## Part 0 — Editor's own grep sweep (before the two agent audits)

Done immediately after adding the 9+1 items, before requesting the
independent audits:

- `architecture.md`'s Mermaid diagram still labeled the Maps node
  "Mapbox (optional, Could-have v1)" — stale, since the decision moved to
  MapKit/Must-have. Fixed: node relabeled, edge changed from dotted
  "optional" to solid.
- `tasks/phase-4-backlog.md`'s own T4.10 entry was never struck through
  (only `tasks/README.md` and `development-plan.md` were) — fixed with a
  strikethrough + "moved to Fase 1" note, matching the other two files.

---

## Part 1 — Blockers found, and fixes applied this pass

| # | Source | Phase | Finding | Fix applied | Files touched |
|---|---|---|---|---|---|
| B7-1 | architect | Fase 1 | `gps_route` contains every accepted point (including anchor-suppressed drift), a superset of what counts toward `distanceMeters` — splits (§4.10), elevation (§4.12), and the map (§5.1) all derive from `gps_route`; naive point-to-point summation would not equal `distanceMeters`, making §4.10 AC3/T1.10's DoD item literally unachievable | Documented the mandatory fix: distance-deriving functions (T1.10, T1.12) must replicate `RunViewModel`'s `stationaryAnchor` acceptance logic (deterministic, no schema change needed), not sum raw deltas | tech-spec.md §2.1b, tasks/phase-1 T1.10/T1.12 |
| B7-2 / B7-P1 | both | Fase 1 | `durationSeconds` is only written in `pause()`/`stop()`, never incrementally — T0.8's Scope claims it's "finalized and saved" only at Stop, and T1.14's crash-recovery DoD requires resuming duration state that was never persisted for a crash mid-active-segment; T1.14's own Scope explicitly forbade the change that would fix this | T1.14's Scope now owns incremental `durationSeconds` persistence (reusing T0.8's existing flush trigger); T0.8's Scope corrected to describe what's actually saved incrementally; added `T0.8` to T1.14's `Depends on`; added a staleness-cutoff note for stale resume offers | tasks/phase-0 T0.8, tasks/phase-1 T1.14 |
| B7-3 | architect | Fase 1 | Auto-pause was specced as reactive to the anchor logic evaluating on GPS fix arrival — but tech-spec §2.1b's own T0.9 retest shows a stationary device receives almost no fixes (1 in 61.8 min), so the trigger could never fire on the exact condition it targets | Auto-pause redesigned as a periodic timer checking elapsed time since the anchor's last confirmed movement, independent of fix arrival — anchor logic itself unchanged, only how it's observed | tech-spec.md §2.1b, product-spec.md §4.11, tasks/phase-1 T1.11 |
| B7-4 | architect | Fase 1/2 boundary | Auto-pause removes the server's only implicit cross-check on `duration_seconds` (routine gaps vs. occasional manual-pause gaps), and product-spec §4.11 had no AC covering duration/pace treatment at all | Added §4.11 AC4; added a tech-spec §2.4 note that `duration_seconds` is intentionally client-asserted, never cross-checked against the `gps_route` timestamp span, by design since T1.2b | product-spec.md §4.11, tech-spec.md §2.4 |
| B7-5 | architect | Fase 1 | Audio cues need `UIBackgroundModes: audio` (not declared anywhere) and `.ambient` (the proposed `AVAudioSession` category) cannot play in background at all — the one category that can't satisfy the feature's own "screen off" use case | Locked category to `.playback` + `.duckOthers`; added the `audio` background mode requirement to tech-spec, T1.13, and pre-launch-checklist §10; added a physical-device-locked-screen DoD item | tech-spec.md §5.3, tasks/phase-1 T1.13, pre-launch-checklist.md §10 |
| B7-6 | architect | Fase 1 | Streak-reminder scheduling only rescheduled "on run completion and app foreground" — logically can never fire for the exact user it targets (someone who hasn't opened the app in days) | Redesigned to schedule N days of dated triggers ahead of time, re-derived/cancelled-and-rebuilt on every open/run-completion instead of a single reschedule; added a DoD item for the "app not opened for ≥2 days" case | tech-spec.md §5.2, tasks/phase-1 T1.16 |
| B7-7 | architect | Fase 1 | §5.1 offered SwiftUI `Map` (iOS 17+, needed for polyline overlays) as a coin-flip alternative to `MKMapView` in an app whose deployment target is locked at iOS 16.0 | Locked the choice to `MKMapView` + `UIViewRepresentable` | tech-spec.md §5.1 |
| B7-8 | architect | Fase 1 | T1.8's own verification method ("inspect `CLLocationManager` call sites") cannot detect the most likely violation: `MKMapView.showsUserLocation`/`UserAnnotation` starts MapKit's own internal location subscription with zero call sites in app code | Forbade `showsUserLocation`/`UserAnnotation` explicitly; require a custom annotation driven by ViewModel state; reworded T1.8's DoD to assert the forbidden APIs are absent (grep-able) and added a battery re-measurement DoD item | tech-spec.md §5.1, tasks/phase-1 T1.8 |
| B7-9 | architect | Fase 2 | The soft-delete design assumed `User.id` could equal `auth.users.id`; under the standard Supabase FK pattern that either cascades (physically deletes the row, defeating soft-delete) or blocks the Admin-API delete entirely — undocumented either way | Added a separate `auth_user_id` column, deliberately decoupled from `User.id`, specifically so Auth-identity deletion never touches the `User` row | database-api-spec.md §1 (ERD), §2.1b, tasks/phase-2 T2.2/T2.22 |
| B7-10 | architect | Fase 2 | A deleted user's JWT stays cryptographically valid until expiry; nothing rejected it, so the client could call `POST /api/profile/complete` post-deletion and silently un-delete the account | Added a §3 rule: any authenticated request from a caller with `deleted_at` set is rejected; added matching DoD items to T2.3 (middleware) and T2.22 | database-api-spec.md §3, tasks/phase-2 T2.3/T2.22 |
| B7-11 | architect | Fase 2 | Deletion was specced entirely server-side — local Core Data `Run` rows (full `gpsRoute`), `SyncMeta`, Keychain session, and `UserDefaults` were never mentioned; a fresh sign-up on the same device would also re-upload the deleted account's runs under the new identity | Added local wipe (Core Data, Keychain, UserDefaults) to T2.22's Scope/DoD, with a DoD item confirming a fresh sign-up sees zero pre-existing runs | tasks/phase-2 T2.22 |
| B7-12 / B7-P4 | both | Fase 2/3 | §2.1b's leaderboard-exclusion guarantee ("T2.18/T3.2 must exclude deleted users") had zero owning DoD item on either job, T2.22 wasn't dependent on T2.18, and retained/historical leaderboard rows would render a blank username once `User.display_name` is cleared | Added `deleted_at IS NULL` exclusion + rebuild-not-upsert clarification to T2.18/T3.2's Scope+DoD; added `T2.18` to T2.22's `Depends on`; added a denormalized `frozen_display_name` field to `LEADERBOARD_ENTRY` so historical rows keep a name after anonymization | database-api-spec.md §1/§2.1b, tasks/phase-2 T2.18/T2.22, tasks/phase-3 T3.2 |
| B7-13 | architect | Fase 2 | Account deletion was an unacknowledged anti-cheat reset (delete-and-recreate wipes `trust_score`) and orphaned any still-`flagged` run belonging to the deleted user, including HIGH-confidence runs that would then wait forever for a reviewer who can't act on a deleted account | Documented the `trust_score` evasion as an accepted v1 risk (not silently unaddressed); added terminal resolution of in-flight `flagged` runs to `rejected` (compensating transaction) as part of deletion | database-api-spec.md §2.1b, tasks/phase-2 T2.22 |
| B7-14 | architect | Fase 2 | The anonymization field list omitted `email` and `avatar_url` (both plainly personal) and never addressed `RUN.gps_route`; unique-constraint collision risk on a second deletion was unaddressed | Rewrote §2.1b to enumerate every `USER` field's post-deletion value explicitly (including a unique-safe anonymized email), and specified `RUN.gps_route` is nulled (row kept, to preserve `PointTransaction.run_id`) | database-api-spec.md §1/§2.1b, tasks/phase-2 T2.22 |
| B7-P2 | planner | Fase 1 | The AC Coverage Matrix had only 2 rows for §4.10 (which has 3 ACs) — row `4.10.2`'s text was actually spec AC3, so AC 4.10.2 (partial split marked clearly) had no row and the numbering was wrong, not just short by one | Split into 3 correctly-numbered rows (4.10.1/4.10.2/4.10.3) matching product-spec's own AC numbering | tasks/README.md |
| B7-P3 | planner | Fase 2 | T2.22's dependency chain (`T2.3 → T2.1, T0.2`) never reached T2.2 — the task that creates the `User`/`deleted_at`/`auth_user_id` columns T2.22 writes to | `Depends on: T2.2, T2.3` (also added `T2.18`, see B7-12) | tasks/phase-2 T2.22 |

---

## Part 2 — Notes: fixed opportunistically this pass (same files already open)

Lower severity than Blockers, but cheap enough to fix while the relevant
section was already being edited for a Blocker above — listed separately
so it's clear these weren't part of the original Blocker set.

| # | Finding | Fix | Files touched |
|---|---|---|---|
| N7-1 / N7-P5 | "31 new rows" claim didn't match the actual (miscounted) row count | Corrected after B7-P2's row fix — 31 is now accurate | tasks/README.md |
| N7-3 | Dangling "/Could" reference to a MoSCoW row that never existed (route map only ever lived in §5 Non-Goals) | Removed the dangling reference | product-spec.md §3 |
| N7-5 | tech-spec §5.1 claimed the map needs "no changes" to `RunViewModel`, but `lastLocation`/`pendingPoints` are `private` — new `@Published` state is genuinely needed | Corrected the framing; clarified no new `CLLocationManager`/Core Data field is needed, only newly-exposed `@Published` state | tech-spec.md §5.1 |
| N7-6 | tech-spec §4 and T0.7's Scope both claimed `pausesLocationUpdatesAutomatically` is used for stop-detection; shipped code sets it `false` | Corrected both to match reality (T0.9's 3%/hour battery measurement was taken with it `false`, target still holds) | tech-spec.md §4, tasks/phase-0 T0.7 |
| N7-7 | Auto-pause's auto-resume limitation (impossible by construction, GPS stops during pause) was undocumented — would read as a bug later | Documented as a deliberate v1 limitation in both the AC and the task | product-spec.md §4.11, tasks/phase-1 T1.11 |
| N7-8 | tech-spec §5.2 cited `user-flow.md §2.1`, an unreconciled draft whose 2-state permission flow is superseded by product-spec §4.15's 3-state design | Repointed the citation to product-spec §4.15/T1.15 | tech-spec.md §5.2 |
| N7-9 | A live `MKMapView` per Run History row is a known scroll-performance trap; neither §5.1 nor T1.9 picked an approach | Specified cached `MKMapSnapshotter` thumbnails for History rows, live `MKMapView` only on Summary/detail | tasks/phase-1 T1.9 |
| N7-10 | pre-launch-checklist §10 implied only `location` would ever be declared, but T1.13 needs `audio` too (B7-5) | Added an explicit `audio` checklist line | pre-launch-checklist.md §10 |
| N7-12 | Streak reminder never addressed the "never had a streak" case — left ambiguous whether that was an oversight | Documented explicitly as a deliberate v1 scope decision (protects existing streaks, doesn't drive first-run acquisition) | tech-spec.md §5.2, tasks/phase-1 T1.16 |
| N7-14 | Diagram edge `UI --> Maps` contradicted architecture §3's own layering rule (Presentation has no independent data access) | Changed edge source to `State`, added a clarifying prose line | architecture.md |
| N7-15 | T0.9's note about the missing resume-UI called it "a separate, un-scoped UX gap" — that gap is now scoped (T1.14) but the note was never updated | Added "(now owned by T1.14)" | tasks/phase-0 T0.9 |
| N7-P1 / N7-P2 | AC 4.13.1/4.16.2 were marked `Yes` but their owning DoD items didn't actually verify announcement *content* or reminder *delivery timing* — only frequency/condition | Both gaps closed directly by the B7-5/B7-6 DoD rewrites above (content + timing/dedupe now covered) — rows genuinely `Yes` now, not downgraded | tasks/phase-1 T1.13/T1.16 (no README change needed) |
| N7-P3 | T1.8 and T1.13 both build on state/paths tech-spec attributes to T1.2b, but neither had `T1.2b` in `Depends on` | Added `T1.2b` to both | tasks/phase-1 T1.8, T1.13 |
| N7-P4 | A split (T1.10) spanning a paused interval would silently inflate its pace — pause gaps have no intermediate points | Added `T1.2b` to T1.10's `Depends on` and a pause-gap DoD item | tasks/phase-1 T1.10 |
| N7-P6 | Stray `T1.7` reference in a Swift doc-comment, missed by the renumbering to T1.17 | Corrected the comment | ios/Laju/Services/Persistence/PersistenceController.swift |
| N7-P7 | development-plan.md's Fase 1 DoD wasn't extended to require the 9 new items work correctly *together* — only their Scope was, while T1.17 (which cites this DoD) already required it | Added the matching Fase 1 DoD bullet | development-plan.md |
| N7-P8 | T2.21's DoD (Phase 2 sign-off checklist) never accounted for T2.22 (account deletion) even though development-plan's Fase 2 DoD lists it independently | Added a T2.21 DoD bullet requiring T2.22 to be verified or explicitly tracked | tasks/phase-2 T2.21 |
| N7-P9 | T1.15's `Reference` didn't point back to pre-launch-checklist §3, even though §3 already pointed at T1.15 | Added the back-reference | tasks/phase-1 T1.15 |
| N7-P13 | T2.2's DoD didn't enumerate the new `deleted_at`/`auth_user_id` columns, unlike every other schema addition from prior rounds | Added a T2.2 DoD item | tasks/phase-2 T2.2 |
| N7-P14 | Apple Watch (T4.14) was added to development-plan/phase-4-backlog but had no product-spec §3/§5 row, unlike every other deliberate deferral | Added a Non-Goals row | product-spec.md §5 |

---

## Part 3 — Notes: resolved 2026-09-13 (product decisions, made after review)

Both notes below required a call only the product owner could make —
raised, explained, decided, and now closed. Neither was a silent
editorial fix; both were implemented (or explicitly declined) only after
the decision came back.

| # | Finding | Decision | Resolution |
|---|---|---|---|
| N7-4 | Two new **Must**-have ACs were flagged as hard-depending on **Should**-have features: §4.9 AC2 (static map) on Run History (T1.5), and initially §4.16 (streak reminder) on "streak indicator" — re-examined during resolution and found weaker than first stated, since §4.16 only needs `StreakTracker`'s (T1.4) already-Must-adjacent computation, not the separate Should-have "streak indicator" UI. The genuine coupling was §4.9 AC2 → Run History only. | **Option (a): promote Run History (T1.5) to Must-have.** | product-spec.md §3 (MoSCoW row), new §4.18 (Run History AC subsection, promoted from a bare MoSCoW row to a full Must-have user-story+AC section), §4.9 AC2's cross-reference updated; tasks/phase-1-core-loop-offline.md T1.5 (Objective + Reference updated, Scope/DoD/Depends-on unchanged — already correct); tasks/README.md (2 new AC rows 4.18.1-4.18.2, checklist line annotated) |
| N7-P11 | T1.11/T1.12's `Depends on` lists T1.2b/T1.2 rather than naming T0.9/T0.8 directly, even though their Objectives credit those tasks by name — cosmetic, dependency graph already correct and complete | **No change.** T0.9 is a verification/gate task, not a code-producing one — the convention that `Depends on` represents code-producing tasks only is preserved by deliberately NOT adding it, even though the Objective's narrative credits T0.9/T0.8. | None — resolved as "no change needed," not left open |

Both items are now closed. No open Notes remain from Round 7.

---

## Part 4 — What was verified intact (unaffected by this round's additions)

- **No dependency cycles, no dangling task IDs, no duplicate IDs** across
  T1.8-T1.17 and T2.22 (verified directly against the task files, not
  assumed).
- **T1.7 → T1.17 renumbering is clean** everywhere in `Laju/documents/` —
  the only surviving `T1.7` string is `audit-report.md`'s own Round 6
  B6-5 entry, correct as historical record of what was true at the time.
- **T4.10's retirement (Mapbox → Fase 1 MapKit) has no dangling
  reference** anywhere in the corpus after Part 0's fix.
- **T4.14/T4.15/T4.16 numbered consistently** across product-spec.md
  (§3 + §5), development-plan.md, tasks/phase-4-backlog.md, and
  tasks/README.md.
- **Social Feed reconciliation is consistent** across every file that
  mentions it, with the Fase-4-not-Fase-3 recommendation clearly flagged
  as a recommendation (not a locked call) everywhere it appears.
- **T2.22 vs T2.21's two-gates argument is sound** (leaderboard
  visibility vs. App Store submission are genuinely different gates) —
  N7-P8 only found the sign-off checklist didn't say so, now fixed.
- **Every AC row newly marked `Yes` in the coverage matrix was checked
  against a real, specific, falsifiable DoD item** in the owning task —
  not a task that merely "touches" the feature. Two rows (4.13.1, 4.16.2)
  needed their owning task's DoD strengthened to earn that `Yes`
  genuinely (done as part of B7-5/B7-6 above) rather than being
  downgraded to `Partial`.
- **The anti-cheat state machine, `excluded_pct`, LOW/HIGH split,
  `REVIEW_WINDOW_LOW`, "only T2.12a owns status", the `GET /api/runs?since=`
  cursor contract, and the region hierarchy** — all re-verified, all
  still internally consistent. This round's additions disturbed only the
  deleted-user interaction with this system (B7-13), not the system
  itself.
- **`mvp-report.md`** has no position on route maps at all (neither §4
  Core Features nor §7 Out of Scope) — the Non-Goal reversal (route map
  → Fase 1) creates no contradiction there.

---

## Part 5 — Methodology note

Per Round 6's own precedent, this round's audit was run as two parallel
subagents (`ecc:architect`, `ecc:planner`) rather than a single pass —
the split surfaced real, non-overlapping findings (e.g. `ecc:architect`
caught the auto-pause reactive-trigger flaw B7-3 that a pure
dependency-graph read would miss; `ecc:planner` caught the AC-matrix
row-numbering bug B7-P2 that a pure architecture read would miss),
confirming the two-lens approach is still worth the cost for a change of
this size (12 new items across 12 files).
