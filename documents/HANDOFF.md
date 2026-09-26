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

**Update, 2026-09-26**: a long PM product-review session (no code written, discussion + doc
updates only) produced a large batch of Fase 4 product decisions — all written into
`product-spec.md` §4.19, §4.20 (flagged, not decided), §4.23-§4.26, and new §4.29-§4.33, plus
`code-quality-audit.md` (new finding CQ-11) and `tasks/phase-4-backlog.md`/`tasks/README.md`.
**Read this before touching any Fase 4 Club/Circle/Premium/Social work — several of these reverse
already-built code, not just docs:**

1. **Club renamed "Circle" in the UI only** (2026-09-26) — internal `club`/API/DB naming is
   unchanged, this is presentation-layer copy only. See product-spec.md §4.24's header note.
2. **`POST /api/clubs`'s Premium gate (added 2026-09-25) must be reverted** — creating a Circle is
   free for every tier again, per product-spec.md §4.24 AC1 (which the 2026-09-25 code had drifted
   from). **Real engineering work outstanding, not done as of this writing.**
3. **Member cap added**: Free Circle 20, Premium Circle 100 (§4.24 AC22) — not yet enforced in code.
4. **Kick-member/transfer-ownership/edit-info/regenerate-code/promote-admin confirmed free for
   every tier** (§4.24 AC23) — corrects a prior wrong assumption that bundled kick-member with the
   Premium-gated admin tools (`tasks/README.md`'s old T4.1b line said "owner-removes-member...
   deferred, blocked on T4.20b" — that was wrong, now corrected).
5. **Circle challenges fully detailed** (§4.24 AC13): automatic participation, collective total
   only ever increases, individual ranking drops a departed member but their own data is untouched,
   reaching the target early doesn't end the challenge before its deadline, owner-cancel now sends
   a real push notification (a narrow, deliberate exception to "no push" elsewhere).
6. **Club War put ON HOLD, not cancelled** (§4.19) — no timeline. T4.2a's applied schema and
   T4.2b's inert `isPremiumClub()` stub are unaffected, stay exactly as built.
7. **Club Global Leaderboard (T4.17, §4.20) has an open, unresolved question** — do not build
   against it until the PM explicitly answers whether it's still needed now that Circle's own
   internal leaderboard turned out to be a cheap reuse.
8. **Premium pricing revised: $1.99/mo, was $7.99/mo** (§4.23 decision #7) — reasoning: the Premium
   bundle is intentionally light (Club War on hold, Circle free), so priced to match, not to match
   Strava's own $9.99-11.99/mo tier.
9. **Profile photo & bio are now free for every tier** (§4.26) — only Alt App Icon stays
   Premium-only. Reversal reason: Social Feed shows post authors' photos; a Freemium user with no
   photo would render broken in a feed meant to drive growth for the whole user base.
10. **New Achievement system, mechanism only** (§4.31): earning is free for every tier; showcasing
    an earned achievement on profile/Social Feed is Premium-only and server-verified. **Explicitly
    NOT the same thing as Personal Record** (§4.25, unchanged, stays inside Advanced Stats). The
    actual achievement content list (names/thresholds) is not decided — the PM is compiling it
    separately.
11. **New: Kartu NFC** (§4.32) — sold separately (merchandise, never grants Premium by itself, App
    Store IAP rules), a secondary auth link (card + PIN, two-factor) to an already-authenticated
    Apple/Google account, ties into a Season top-10 physical reward (opt-in claim + extra manual
    anti-cheat verification).
12. **New: real-time anti-cheat warning during tracking** (§4.29) — 5 consecutive speed-jump
    detections within 2 minutes triggers a warning; ignoring it results in 0 points + a heavier
    trust-score penalty at Finish. **Hard-blocked on CQ-11** (see below) being fixed first.
13. **New: triple back-tap to trigger Start** (§4.30) — via an App Intent/Shortcut the user must
    bind manually in iOS Settings; Laju cannot enable or detect this automatically.
14. **New: Social Feed Feed/Friends segments + one-way follow** (§4.33), extending the already-live
    T4.15 — "Friends" is a computed mutual-follow filter, not a second data model. A standalone
    free-text (Twitter-style) post type was considered and explicitly rejected.
15. **New bug found, not yet fixed: CQ-11** (`code-quality-audit.md`) — the live/instant pace shown
    during tracking has no defined smoothing/windowing rule (unlike the stable `avg_pace_sec_per_km`
    used for points, which is unaffected). Reported as "kadang melompat, kadang tidak sesuai dengan
    kecepatan aslinya." This is now also a hard prerequisite for item 12 above.

None of items 2-4, 12, 13, 15 have any code written yet — this session was discussion + documentation
only, no Senior iOS Developer work was dispatched. Next session's job is to turn the above into
real, checkpointed implementation tasks (one at a time, per this file's own workflow contract in §1).

**Audit drift 2026-09-26** — full read of the code against the 2026-09-26 doc update above (audit
only, zero production code touched, per its own task instructions). Numbered against that task's own
8 checklist points:

1. **Club War stub — no drift.** `backend/lib/club-war/premium.ts`'s `isPremiumClub()` still
   unconditionally returns `false`, no env flag, no bypass. No new Club War scope added anywhere in
   `backend/app/api/club-wars/`. Matches "on hold" exactly.
2. **`POST /api/clubs` Premium gate — real contradiction, confirmed.**
   `backend/app/api/clubs/route.ts:72-74` still calls `isPremiumUser` and 403s `not_premium` for
   every non-Premium caller. Directly contradicts §4.24 AC1 ("any tier can create"). iOS side has
   the matching gate: `CreateClubView.swift:23-24` swaps the form for `PremiumUpsellView` on
   `model.isPremiumRequired`. Both need reverting — real engineering work, not done.
3. **Member cap — confirmed absent, not a contradiction.** `backend/app/api/clubs/[id]/join/route.ts`
   has zero count/limit logic of any kind — checked the full file. This is new scope decided
   2026-09-26 (after the 2026-09-25 code), so absence is expected, not drift.
4. **Kick-member — confirmed absent, PLUS a stale comment worth flagging.**
   `backend/app/api/clubs/[id]/members/route.ts`'s `DELETE` handler is self-leave only (`.eq(
   "user_id", user.id)`, no `:userId` path param) — no owner-removes-member endpoint exists. Its own
   doc comment currently reads *"owner-removes-member is admin tooling, deferred behind T4.20b same
   as everything else Premium-gated"* — this comment is now factually wrong per §4.24 AC23 (kick-
   member confirmed free for every tier, not admin/Premium tooling) and should be corrected/removed
   whenever this endpoint is actually built, not just left as-is.
5. **Freeze policy — confirmed absent.** No challenge/analytics endpoint exists anywhere under
   `backend/app/api/clubs/` at all (only `route.ts`, `[id]/join/`, `[id]/members/`), so there is
   nowhere for above/below-cap freeze logic to live yet. New scope, not drift.
6. **"Club" vs "Circle" copy — full location list, none changed yet (audit only, as instructed).**
   User-facing "Club" strings found: `RootTabView.swift:69` (tab label), `RanksView.swift:19-20`
   (segmented control) `:44-45,53-54` (empty-state titles/body copy, Indonesian), `ClubHomeView.swift
   :27,45,62,66` (nav title, "Browse Clubs"/"Club Saya"/"Club War" buttons), `ClubBrowseView.swift:28`
   (nav title), `CreateClubView.swift:29` (nav title), `ClubMemberListView.swift` (doc-comment only,
   mentions a "Leave Club" button whose actual label needs checking against whatever the button text
   literally is when this gets built). **Open question for the PM, not assumed:** `ClubWarView.swift`
   also says "Club War" (`:37` nav title, `:53` card title) and `ClubWarPreviewData.swift:25` says
   "Club Kamu" — product-spec.md §4.24's rename note covers the base Club feature explicitly but
   §4.19 (Club War) has no equivalent rename note either direction. Does "Club War" become "Circle
   War" too, or does War intentionally keep the old name? Not guessed here.
7. **CQ-11 root cause — confirmed present, but the doc's own speculated mechanism is wrong.**
   Live pace (now displayed as live speed after this session's separate km/h change — same
   underlying value) is computed in `RunTrackingView.swift`'s `liveSpeedLabel` (was `livePaceLabel`)
   as `liveActiveDuration() / (distanceMeters / 1000)` — i.e. **whole-run cumulative average**,
   recomputed on every UI tick from the SAME two running totals the stable `avg_pace_sec_per_km`
   uses at Stop. CQ-11 speculates the likely cause is "computes pace from the last one or two GPS
   samples directly" — **that read of the code is not what's happening; there is no last-N-samples
   logic anywhere in this path.** The real, evidence-based mechanism: early in a run, the
   denominator (elapsed active duration) is small, so each newly-accepted GPS movement chunk (10-20m
   steps past the stationary-anchor filter, `RunViewModel.swift:295-336`) swings the cumulative
   average sharply; later in a run, the same-size chunk is diluted by a much larger denominator and
   barely moves it. This matches "kadang melompat, kadang tidak sesuai" (jumps early, settles later)
   better than a raw-instant-velocity theory would. CQ-11's core finding (no defined
   windowing/smoothing rule) still holds — only the specific guessed mechanism needed correcting
   before a fix task designs around it.
8. **General sweep — clean, nothing else found.** Grepped `backend/` and `ios/` for stale `$7.99`/
   `7.99` pricing and any "no push"/"never send push" assumption in code comments — zero hits in
   either. `tasks/README.md`'s T4.1b/T4.1c lines were already corrected by the PM's own reconcile
   commit (`60eb675`) before this audit started — confirmed consistent with everything found above,
   not a new finding.

Nothing above was fixed — audit only, per this task's own instructions. Next session: turn items
2-6 into real, checkpointed implementation tasks one at a time (same workflow contract as §1),
starting with item 2 (the live contradiction) and item 6's open question (needs the PM's answer
before any Club War copy is touched).

**Update, 2026-09-24**: real device dogfood (Google sign-in, not Apple) surfaced product feedback,
acted on the same day (commits `07e7a6b`, `b33add4`, `6ec3cc0`) — no task number owns this, it's
ad-hoc PM-directed nav/UX work, not part of the phase-N task files:
- **Navbar restructured to 5 tabs**: Social, Club, Track, Ranks, You (`RootTabView.swift`). Social
  (T4.15) and Club (T4.1) have no real content yet — each shows a `ComingSoonView` placeholder, added
  now so the order is right rather than waiting for those features.
- **Club War moved** from a DEBUG-only scaffold link buried in the You tab to a real, always-visible
  entry in the new Club tab (`ClubHomeView.swift`). Ungating from `#if DEBUG` is safe: the backend
  (`backend/app/api/club-wars/`, T4.2b) is real deployed code, not a stub — it deliberately denies
  every caller with 403 `not_premium_club` until T4.20 (Premium) ships, and the iOS error map already
  handles that response gracefully.
- **Ranks tab got a 3-way segmented toggle** (Users/Club/Club War, `RanksView.swift`). Only Users
  (the existing global leaderboard) is real — Club and Club War leaderboards have no owning
  task/endpoint (checked: no such code anywhere in `backend/` or `ios/`); this is a **gap**, not
  scheduled work — no T4.17 (Club Global Leaderboard) code exists yet despite it being discussed.
- **Logout added**, separate from the existing Delete Account — `AuthService.signOut()`, clears only
  the local session (never touches Core Data or `UserDefaults`, unlike account deletion). A
  previously-onboarded user who logs out now skips the full onboarding flow and lands directly on a
  sign-in screen (`ReturningSignInView.swift`) instead of `OnboardingContainerView`; a brand-new user
  is unaffected. Root gating logic: `LajuApp.swift`.
- **Verification**: `xcodebuild build` and `test` both green (193/193), SwiftLint 0 violations,
  SwiftFormat clean. **Not yet verified on a physical device** — this needs the user's own dogfood
  pass (tab order/icons, Club War still reachable and functional, logout → sign back in → lands on
  Track not onboarding, a brand-new install still gets full onboarding).

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
  never closes and no new one starts. ~~Also note T4.18 (60-day seasons from Season 2) is decided but
  **not implemented**, so creating Season 2 means either implementing T4.18 first or creating it by
  hand with a 60-day period (`backend/scripts/season.ts`).~~ **Decided 2026-09-23 (T4.18): Season 2
  is created by hand** with `backend/scripts/season.ts create`, 60-day period. Don't copy the script
  header's example dates — they give ~90 days. Overrun is still silent until T4.18's warning-log
  todo ships. Reminder only — not queued work; raise it with the user well before the date.

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
Only T4.20a (the `subscription` table) is buildable before enrollment — unblocked 2026-09-23
(`user_id` is a non-null FK, product-spec.md §4.23 AC14). The user is enrolling in the paid Apple Developer
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
- **Club display name is "Circle" — UI copy only, internal `club` naming unchanged** — decided
  2026-09-26 (PM decision, product review session), reverses the *other* direction taken just 3
  days earlier (2026-09-23, "Circle"→"Club" to match existing `club_id` code). Full detail:
  product-spec.md §4.24's header note.
- **Circle creation is free for every tier, not Premium-gated** — decided 2026-09-23
  (product-spec.md §4.24 AC1), **the 2026-09-25 code (`POST /api/clubs`) drifted from this
  decision and needs reverting** — see §3 item 2 above. Member cap (Free 20 / Premium 100) added
  2026-09-26 as the actual Free/Premium differentiator for Circle capacity (§4.24 AC22).
- **Club War is on hold, not cancelled** — decided 2026-09-26 (PM decision), no timeline set. See
  product-spec.md §4.19's header note.
- **Premium price is $1.99/mo, not $7.99/mo** — revised 2026-09-26 (PM decision), reverses the
  2026-09-23 figure. Still monthly-only, no annual plan, no free trial (unchanged). Full
  rationale: product-spec.md §4.23 decision #7.
- **Profile photo and bio are free for every tier** — revised 2026-09-26 (PM decision), reverses
  the 2026-09-24 figure (product-spec.md §4.26 AC1-AC2). Only Alt App Icon remains Premium-only.

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
