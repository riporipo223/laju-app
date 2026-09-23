# Laju — Session Handoff

**Read this file first, completely, before touching anything else.** You are a new Claude Code
session — different device, different account, no memory of any prior conversation. This file is
written so you don't need that memory. It is a map, not a full briefing: it tells you what to read
next and in what order, not everything about the project.

If the user's first message is just **"Lanjutkan"** ("continue"), read this whole file, then go to
§3 before doing anything else.

---

## 0. Reading order — don't read everything, read in this order and stop when you know enough

1. **This file** (2 minutes).
2. **[documents/README.md](./README.md)** — §5 "Status at a glance" for phase status, plus the
   banner at the top. Read §1/§2/§3 only if your task touches Fase 1 or Fase 2 (Fase 3 is closed,
   Fase 4 is not scheduled).
3. **[documents/03-development/tasks/README.md](./03-development/tasks/README.md)** — the task
   checklist. Treat it as *probably* correct, not certainly — see §1 below.
4. **Only the one `phase-N-*.md` file** that owns the task you're about to touch. Don't read the
   other phase files unless your task explicitly references them.
5. **Only the specific section** of `product-spec.md` / `tech-spec.md` / `database-api-spec.md` that
   the task's own `Reference:` line points to. Don't read these documents cover to cover.

Do not read all 20+ documents in `documents/` up front. That is slower than reading the four things
above and looking up anything else only when a task actually needs it.

---

## 1. How this project works — the workflow contract

This project has a specific way of working. Follow it exactly; it is not a suggestion.

- **One task at a time.** Implement it, verify it with **real evidence** (an actual test run's
  actual output — `186/186 passing`, an actual `curl`/`psql` result against the real database, a
  real `xcodebuild test` log — never "this should work" or "tests should pass now"), update that
  task's own checklist/DONE block **only after** its Definition of Done items are genuinely true,
  then **stop and wait for the user to type "Lanjutkan"** before starting the next task. Do not
  chain multiple tasks together in one turn without that checkpoint.
- **`tasks/README.md` is the intended source of truth, but it drifts stale.** This has happened
  more than once in this project (most recently: T3.1 shipped in code on 2026-09-21 but its
  checklist was never marked done — caught and fixed 2026-09-22, days later, only because a later
  gate task's dependency list forced a re-check). **Always cross-check the checkbox in
  `tasks/README.md` against the actual `DONE`/status block inside the relevant `phase-N-*.md`
  file** before trusting either one in isolation. If they disagree, the `phase-N-*.md` file's own
  DONE block (with its evidence) is more likely correct — but say so and fix the checklist rather
  than silently picking one.
- **An ambiguous product or technical decision with no answer in any document → stop and ask the
  user.** Do not decide it yourself and keep going. The one exception: small mechanical fixes —
  a broken link, a typo, an obviously stale cross-reference — just fix those inline as you notice
  them, no need to ask or make a fuss about it.
- **Reuse existing, already-tested logic. Do not reimplement it from scratch.** In particular:
  - GPS filtering / stationary-anchor drift logic — `ios/Laju/ViewModels/RoutePointBuffer.swift`
    and `ios/Laju/Services/Location/LocationTrackingService.swift` (see ADR 0004).
  - The point formula — `ios/Laju/PointFormula/PointFormula.swift` (client) and
    `backend/lib/point-calculation.ts` (server) — these two must stay in parity (ADR 0007) via a
    shared fixture file; don't hand-edit one without the other.
  - Auth — `ios/Laju/Services/Auth/AuthService.swift` / `SupabaseConfig.swift` (client),
    `backend/lib/auth.ts` (server, `requireUser`/`requireAuthenticatedIdentity`).
  
  Grep for existing logic before writing new logic that looks similar.

---

## 2. Current status (snapshot — `tasks/README.md` has the real detail, this is just orientation)

| Phase | State |
|---|---|
| Fase 0 — Setup | Closed. |
| Fase 1 — Core Loop Offline | Code complete. Gate (T1.17) open — needs physical-device dogfood runs only the user can do. |
| Fase 2 — Backend + Sync + Global Leaderboard | 26/33 closed, 4 PARTIAL. All 4 PARTIAL items blocked on the Apple Developer Program (see §4) or a real device. |
| **Fase 3 — Season** | **DONE, 2026-09-22.** All 7 tasks (T3.1, T3.6, T3.7, T3.7a, T3.8, T3.9, T3.10) complete and signed off — see [phase-3-season.md](./03-development/tasks/phase-3-season.md)'s T3.10 sign-off block. T3.1 (region onboarding) was superseded 2026-09-22 and **fully reworked 2026-09-23** — region removed entirely, live in production. See §5. |
| Fase 4 — Backlog (T4.1+, Club/monetization/etc.) | **Not scheduled. Do not build without explicit user go-ahead.** Local Leaderboard (former T3.2–T3.5) is a separate case: **cancelled permanently 2026-09-22**, not part of this "not scheduled, ask first" backlog — it will never be scheduled, don't offer it as an option. |

---

## 3. If the user types "Lanjutkan" right now

**Update, 2026-09-23**: the `luvfr` branch (12 commits: CQ-2, SEC-1, auto-pause removal, Local
Leaderboard cancellation + full region removal) was independently re-audited from scratch, merged to
`main` (`99cd7ef`), and Task B's migration was applied for real to production. Everything below is
now **closed and live**, not just merged:

- **CQ-2, SEC-1, auto-pause removal (T1.11)** — all closed 2026-09-22, verified again during the
  merge audit. See `code-quality-audit.md` (CQ-2), `security-review.md` (SEC-1) for full detail.
- **Region removed entirely, Leaderboard gated on location permission (Task A/B/C of the D1
  reversal)** — fully done and live as of 2026-09-23. `region_kecamatan`/`region_kabupaten_kota`/
  `region_provinsi` are **physically gone** from the production `user` table (migration
  `20260923090000`, applied and verified: 0 columns remain, the new check constraint genuinely
  rejects a regional `leaderboard_scope`/`leaderboard_entry` insert). `LocationAuthorizationObserver`
  + `LeaderboardLockedView` are live; confirmed with a real request against the live backend
  (`POST /api/profile/complete` with no region fields → `201`).
- **Two real bugs were found and fixed during the merge audit, not by the original session**: (1)
  a Swift 6 data-race compile error in `LocationAuthorizationObserver.swift` that had never
  actually been built (the machine that wrote it has no Xcode) — CI's `Build + test` step was
  failing on it; (2) `lib/account-deletion.ts` was still nulling the three region columns on every
  account deletion, which — once the migration above actually ran — would have made `DELETE
  /api/account` fail for every real user (PostgREST rejects unknown columns). Both fixed and
  verified live (a real `DELETE /api/account` call now returns `200 {"deleted":true}` post-migration).
  A stale Privacy Policy claim ("we collect your wilayah/region") was also caught and fixed in both
  languages (`backend/lib/legal.ts`) — region collection stopped days before this policy text did.
- The `luvfr` branch itself is now merged and historical — a future session should branch fresh from
  `main`, not continue pushing to `luvfr`.

Nothing is queued next. Fase 4 is explicitly "do not build." Do not guess and start building
something from Fase 4. Tell the user where things stand and ask which of the following they want
tackled — each still needs either a user decision or something only the user can physically do:

- **T1.17 gate** — needs physical-device dogfood sessions (battery-with-map-on-screen, audio cue
  with screen locked, ≥5 runs across ≥3 days). User-only; you cannot do this.
- **T2.3/T2.22/T2.21 remaining items** — all blocked on the Apple Developer Program, see §4.
- **Fase 4 backlog** (Club, monetization, etc. — several items now have more decided detail as of 2026-09-23, see phase-4-backlog.md, still all "ask first") — only if the user explicitly asks to start
  it. Local Leaderboard specifically (former T3.2–T3.5) is **cancelled permanently**, not part of
  this "ask first" backlog — don't offer it as an option, it will never be scheduled.
- **Operational deadline — Season 2 must exist before 2026-11-30** (added 2026-09-23). Season 1
  ends 2026-11-30 and **no successor Season row has been created**. Nothing crashes if this is
  missed — `advance_seasons` never leaves zero active seasons, so Season 1 just stays `active` past
  its end date and is reported as `overrun` (database-api-spec.md, Season lifecycle) — but the season
  never closes and no new one starts. Also note T4.18 (60-day seasons from Season 2) is decided but
  **not implemented**, so creating Season 2 means either implementing T4.18 first or creating it by
  hand with a 60-day period (`backend/scripts/season.ts`). Reminder only — not a product decision,
  not queued work; raise it with the user well before the date.

Full detail on all of these: `documents/README.md` §1 and §3.

---

## 4. The recurring blocker: Apple Developer Program

You will hit this repeatedly across open Fase 1/2 items. Write it down once here so you don't
re-derive it every time: the Apple ID currently signed into this machine's Xcode is a **free
Personal Team**, and Apple does not allow a Personal Team to carry the **Sign in with Apple**
capability — confirmed live via `xcodebuild`: *"Personal development teams... do not support the
Sign In with Apple capability."* This blocks Sign in with Apple's end-to-end verification, some
T2.21 gate items, and T2.22's real-device half — and, added 2026-09-23, ~~**App Store Server
Notifications for Premium (T4.20, product-spec.md §4.23)**: the target design for real-time
subscription status sync, deliberately not built until enrollment.~~ **all of Premium's server
side (T4.20b) and its real App Store products (T4.20c), not just App Store Server Notifications**
(corrected 2026-09-23 after checking Apple's docs: every App Store Server API call needs a key
generated in App Store Connect, and App Store Connect is paid-membership-only). Knock-on: every
server-side Premium check waits on this — T4.2b (Club War) and §4.5 AC4 league gating included.
Only T4.20a (the `subscription` table) is buildable before enrollment. The user is enrolling in the paid Apple Developer
Program separately; until that lands, treat these as **accepted PARTIAL/open items**, not bugs to
work around. A `DEBUG`-only escape hatch already exists for automated E2E testing without a real
Apple sign-in — see `AuthService.swift`'s `LAJU_DEBUG_ACCESS_TOKEN`/`LAJU_DEBUG_REFRESH_TOKEN`
env-injected session (real Supabase tokens for a throwaway test user, not a bypass of server auth).
Don't build a different workaround; use that one if you need to exercise a post-sign-in flow on a
Personal Team build.

---

## 5. Decisions that are FINAL — do not relitigate without explicit user approval

One-liners only. Full rationale: `documents/02-architecture/adr/README.md` (13 ADRs) and
`documents/README.md` §3's "Closed" tables.

- Native Swift + SwiftUI, not React Native (ADR 0001).
- Core Data, not SwiftData (ADR 0002).
- `CLLocationManager` directly, no third-party GPS library (ADR 0003).
- Stationary-anchor drift filter for GPS, not a simple distance threshold (ADR 0004).
- Next.js + Supabase + Vercel backend stack (ADR 0005), Postgres not Firestore (ADR 0006).
- Shared fixture file keeps client/server point-formula in parity — never let them drift (ADR 0007).
- Server-side anti-cheat is architecturally separate from client-side sanity filtering (ADR 0008).
- Minimum-distance gate on the point formula, anti-farming (ADR 0009) — do not weaken it.
- MapKit, not Mapbox (ADR 0011).
- Append-only `point_transaction` ledger + a separately precomputed leaderboard table — never
  derive the leaderboard live from the ledger on read (ADR 0013).
- **Apple AND Google Sign-In**, not Apple-only — Google added 2026-09-21 as a second provider.
- **Leaderboard is Global-only, permanently — Local/regional leaderboard (T3.2–T3.5) is
  CANCELLED, not deferred** — reversed 2026-09-22 (PM sign-off) from the prior "moved intact,
  waiting on user density" position. Rationale: scope too broad for the leaderboard logic needed,
  not a density/timing problem. `product-spec.md` §4.6, `tasks/phase-4-backlog.md` T3.2–T3.5 kept
  struck through as historical record; will never be built.
- **"Tier" = Season League** — a division computed from points earned *in the current season
  only*, resets every season. It is not Level (lifetime) and not Rank. `tech-spec.md` §2.5.
- **Region (kecamatan/kabupaten/provinsi) is REMOVED from v1 entirely** — reverses the prior
  "mandatory in v1 onboarding" decision (D1, 2026-09-21), reversed 2026-09-22 (PM sign-off) as a
  direct consequence of the Local Leaderboard cancellation above (region was collected specifically
  to prepare for that feature). Not replaced with GPS-based text detection — just removed. **Live
  2026-09-23**: `region_*` columns physically dropped from production (`20260923090000`), no code
  reads or writes them.
- **Global leaderboard visibility is gated on granted location permission, not on region** —
  decided 2026-09-22, the replacement mechanism for the region removal above. Boolean/status only
  (`CLLocationManager` authorization state) — no place name, no reverse geocoding, no admin
  hierarchy stored anywhere. Reuses the existing run-tracking location-permission infrastructure,
  no second permission flow. **Live 2026-09-23** (`LocationAuthorizationObserver` +
  `LeaderboardLockedView`, merged `99cd7ef`). See `product-spec.md` §4.5 AC5 — its permission-denied
  fallback (a locked Leaderboard tab + Settings CTA) is flagged there as the PM's stated assumption,
  still not confirmed in detail even though it's built.
- `resolve-flagged-runs` cron runs **daily**, not ≤12h — Vercel Hobby plan limitation, accepted
  (OPS-1). Revisit only if/when the project upgrades to Vercel Pro.
- `POST /api/runs` p95 latency currently **does not** meet the 1.5s budget (PERF-1) — accepted
  limitation pending a possible Supabase Pro upgrade, not being actively optimized right now.
- **GPS route retention is indefinite, until account deletion** — decided 2026-09-22 (SEC-1), both
  server-side (`RUN.gps_route`) and locally (`Run.gpsRoute`). Deliberate: full run history is a
  core product feature. Revisit only if UU PDP legal review (SEC-12, still open) or a real incident
  changes the calculus — see `security-review.md` SEC-1 for the alternatives considered.
- **Auto-pause (T1.11, product-spec.md §4.11) is removed from v1 entirely** — decided 2026-09-22
  (PM sign-off), not disabled: code deleted (`AutoPauseWatchdog.swift`, `AutoPauseThreshold.swift`,
  their tests, and the wiring in `RunViewModel.swift`/`RunTrackingView.swift`). The
  `stationaryAnchor` drift-guard GPS filtering it reused (ADR 0004) was **not** touched — that
  logic stays, it's core GPS noise filtering used elsewhere. T1.17's gate no longer covers it (now
  8 items, not 9). Correction while acting on this: the removal request cited T1.10, but T1.10 is
  actually splits-per-km — auto-pause is T1.11 (verified against tasks/phase-1-core-loop-offline.md
  before touching any code).
- **User Season length changes 91→60 days, but forward-only — Season 1 stays 91 days, unmodified**
  (T4.18, decided 2026-09-23, PM decision). The **currently live** `Season 1 — 2026`
  (2026-09-01→2026-11-30) finishes on its original schedule; the 60-day cadence starts with Season 2.
  Reason: cutting a live season short mid-run breaks the trust of users who invested effort under the
  original 91-day expectation. **Not implemented yet — the live season row and any season-length
  constant are untouched.** Do not touch them without a separate, explicitly scoped task (see
  tasks/phase-4-backlog.md T4.18). Full detail: product-spec.md §4.20.

---

## 6. Security — read before your first commit, every session

This repo (`riporipo223/laju-app`) is **public**. There has already been one real incident (a key
exposed in this repo) — do not repeat it. Before any `git add`/`git commit`:

- **Supabase `service_role` key: NEVER a literal value in any tracked file, ever.** Only as an
  env var reference (`process.env.SUPABASE_SERVICE_ROLE_KEY`), sourced from `.env.local` (backend,
  gitignored) or CI/Vercel secrets. If you ever see a literal JWT next to the word "service_role" in
  a diff, stop and do not commit.
- **The Supabase *anon* key is meant to be public.** `ios/Laju/Services/Auth/SupabaseConfig.swift`
  embeds it in the client binary on purpose — Supabase's security model is Row Level Security, not
  key secrecy. Seeing it there is correct, not a leak. Don't "fix" it.
- **Google OAuth**: only a Client *ID* may appear anywhere (public by design). A Client *Secret*
  (`GOCSPX-...`) must never appear in any tracked file.
- **Apple**: no `.p8`/`.p12`/`.mobileprovision` file should ever be added to git.
- Read every file in `git diff --cached` yourself before committing — don't assume `.gitignore`
  alone catches everything, and don't assume a file removed later is scrubbed from git *history*
  (`git log --all --full-history -- <path>` checks that; `.gitignore` only stops *future* commits).
- `documents/` is gitignored almost entirely on purpose (business docs — lean canvas, MVP report,
  full tech spec — stay private, not published on the public repo). **This file and
  `documents/README.md` are a deliberate, narrow, explicit exception** (added 2026-09-22, user
  decision) — see the `!documents/HANDOFF.md` / `!documents/README.md` lines in the root
  `.gitignore`. Do not widen that exception to other files in `documents/` without asking the user
  first — that would newly-publish 20+ documents that were kept private on purpose.

---

## 7. Where things live

- **iOS app**: `ios/Laju` (SwiftUI, Core Data). `ios/project.yml` is the real source — it's fed to
  XcodeGen to generate `ios/Laju.xcodeproj` (gitignored, regenerated, don't hand-edit it if you can
  help it; if you must add a file to a target without XcodeGen installed, edit
  `project.pbxproj`'s `PBXBuildFile`/`PBXFileReference`/group/`Sources` phase sections directly —
  see any recent commit that added a new Swift file for the pattern).
- **Backend**: `backend/` — Next.js API routes + Supabase Postgres, deployed on Vercel at
  `https://backend-eight-gules-56.vercel.app`. Pushing to `main` auto-deploys.
- **Task tracking**: `documents/03-development/tasks/README.md` (index) +
  `documents/03-development/tasks/phase-N-*.md` (one file per phase, DoD blocks with evidence).
- **This file**: `documents/HANDOFF.md` — keep it updated when a phase closes or a major decision
  is made; it's the first thing the next session reads.
