# Phase 3 — Season System

Source: [development-plan.md](../development-plan.md) Fase 3

> **FILE-WIDE CORRECTION, 2026-09-22 (PM sign-off).** Two decisions this file was written under
> have since been reversed: (1) Local Leaderboard is **cancelled permanently**, not "deferred to
> Fase 4 / v1.1" — every "deferred"/"ditunda" phrasing about it below is stale, including inside
> completed-task prose (T3.6/T3.7's dependency notes, T3.10's sign-off text), which is left as
> written because those are historical records of what was true when each task closed; (2) decision
> D1 (region mandatory) is **reversed** — region is being removed entirely, so T3.1 is superseded
> and needs rework (see its own banner below). Current spec: product-spec.md §4.1, §4.5 AC5, §4.6.
>
> **Renamed 2026-09-21** from `phase-3-local-leaderboard-season.md`. The
> Local Leaderboard was cut from MVP v1 and deferred to Fase 4 / v1.1
> (product decision — it needs high user density to be useful; see
> product-spec.md §4.6). This file is now **Season only** plus T3.1
> (region-onboarding UX). The Global Leaderboard is not part of this
> phase at all: it is fully built in Fase 2 (T2.18 precompute, T2.19
> endpoint, T2.20 screen), so nothing Global was lost in the split.
>
> **T3.2–T3.5 moved intact** to [phase-4-backlog.md](./phase-4-backlog.md)
> ("Deferred from MVP v1 — Local Leaderboard"), IDs unchanged. The gap in
> numbering below (T3.1, then T3.6) is deliberate — no renumbering, so
> existing references stay valid.

Dependency note from development-plan.md: this phase depends on Fase 2's
anti-cheat and global precompute (T2.18) already being solid — the season
rank reset re-scopes that same job to a new `season_id`, so any gap carried
over from Fase 2 shows up here.

---

### T3.1 — Mobile onboarding UX blocking run-start until region is set — **SUPERSEDED 2026-09-22, needs rework**

> **SUPERSEDED 2026-09-22 (PM sign-off), same day this phase closed.** Decision D1 (region
> mandatory) is **reversed** and Local Leaderboard is **cancelled permanently** (product-spec.md
> §4.1 / §4.6) — so the entire premise of this task is gone: region is being removed from
> onboarding and from the database, not merely left unused. Everything below is the **shipped,
> signed-off implementation as built** (`8002079`, 2026-09-21) and is kept verbatim as a historical
> record; it is **not** the current spec. The rework — remove the region step, gate Leaderboard
> visibility on granted location permission instead (product-spec.md §4.5 AC5) — is Task C of the
> reversal and is **not done yet**. Do not treat this task's DoD below as describing current
> intended behavior.

**Objective:** Give users a clean client-side experience around the
region requirement — the backend guarantee itself (`409 Conflict` on
`POST /api/runs` for users with no region) already shipped in Fase 2
(T2.5), mirroring the Season pattern (minimal backend guard early, full
UX later). This task is purely additive UX: stop the wasted network
round-trip and give the user a clear in-app reason, rather than
re-implementing enforcement that already exists.

**Scope:**
- Yang dikerjakan: mobile onboarding blocks the run-start flow client-side
  until kecamatan + kabupaten/kota + provinsi are all set (product-spec
  AC 4.1.2), so the user never hits T2.5's `409` in normal use.
- Yang TIDAK dikerjakan: the backend `409` guard (already built, T2.5 in
  Fase 2) or the profile completion endpoint itself (T2.4) — this task is
  mobile-only.

> ~~**Note 2026-09-21:** the Local Leaderboard that motivated collecting
> region is deferred to Fase 4 (product-spec.md §4.6), so no v1 screen
> reads region yet. This task stays in v1 as-is because the shipped backend
> guard (T2.5) still requires a region, and without this UI a new user
> could never submit a run. **Region stays mandatory in v1 — decision D1 is
> FINAL (2026-09-21):** low cost (one field), clear benefit (data ready for
> the Local Leaderboard, no re-onboarding of existing users later).~~ **D1
> REVERSED 2026-09-22 — this note no longer holds: Local Leaderboard is
> cancelled permanently (not deferred), so there is no future feature to
> prepare region data for, and region is being removed from onboarding and
> the schema entirely. See the SUPERSEDED banner at the top of this task.**
> ~~This task
> and T2.5's guard stand unchanged.~~ **(Both are now being removed — T2.5's
> region `409` guard is replaced in Task C.)**

**Depends on:** T2.4

**Reference:** [product-spec.md](../../01-product/product-spec.md) AC 4.1.2,
[database-api-spec.md](../../02-architecture/database-api-spec.md) §3

**Definition of Done:**
- [x] Mobile app blocks the run-start flow (or blocks sync) until all 3
      region fields are set, before any network call is made
- [x] Confirmed (not re-implemented) that the backend still returns `409`
      per T2.5/database-api-spec.md §3 as a defense-in-depth fallback

**Verified done 2026-09-22 (T3.10 gate).** Shipped in `8002079` (2026-09-21,
"add profile step so new users can submit runs") but this checklist was never
closed out at the time — found and fixed while verifying T3.10's dependency
list. `OnboardingStep.profile` (`OnboardingContainerView.swift`) sits between
sign-in and the location prompt: `OnboardingProfileStep`/`ProfileSetupViewModel`
require all 3 region fields non-empty before `POST /api/profile/complete` is
even called, and `RootTabView` (hence any run-start/sync path) is unreachable
until `OnboardingContainerView`'s `onComplete` fires — which happens only after
that step (or is skipped only when the account already has a profile, i.e.
already has a region). So no network call that needs a region can occur before
one is set, satisfying DoD item 1 by construction. Backend `409` fallback
(T2.5) is unchanged, confirmed by the code's own comment
(`ProfileSetupViewModel.swift`: "AC 4.1.2 / T2.4 / T3.1").


---

### T3.2–T3.5 — ~~moved to Fase 4 (Local Leaderboard, deferred)~~ **CANCELLED PERMANENTLY 2026-09-22**

Not part of this phase. See [phase-4-backlog.md](./phase-4-backlog.md),
section "Deferred from MVP v1 — Local Leaderboard". IDs kept as-is.
**Update 2026-09-22 (PM sign-off): cancelled permanently, not deferred** —
scope too broad for the leaderboard logic needed. These four will never be
scheduled; the section in phase-4-backlog.md is a historical record only.

---

### T3.6 — Season lifecycle management (upcoming → active → ended)

**Objective:** Give the season entity real state transitions on top of
the minimal single seeded `active` row Fase 2 (T2.17) already ships —
Fase 2 only needed a season to exist for `PointTransaction`/leaderboard
scoping, not to change state; this task adds the actual lifecycle.

**Scope:**
- Yang dikerjakan: scheduled job (or admin-triggered transition) moving a
  `Season` through `upcoming → active → ended`, ensuring at most one
  `active` season at a time.
- Yang TIDAK dikerjakan: what happens to leaderboards on transition (T3.7
  handles rank reset).

**Depends on:** T2.17

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §1 (Season entity)

**Definition of Done:**
- [x] A season can be transitioned through all three states correctly —
      `season-lifecycle.integration.test.ts` carries a season upcoming → active → ended
      through the real functions (`transition_season` for the explicit step,
      `advance_seasons` for the automatic one), plus catch-up of several missed seasons,
      cancel (upcoming → ended), and every illegal move raising (ended is final, no
      active → upcoming, unknown id, bad target)
- [x] Invariant enforced: never more than one `active` season
      simultaneously — by the database itself: partial unique index
      `season_single_active` (a second active insert fails with `23505`, tested), and both
      lifecycle functions take a transaction-scoped advisory lock so the hourly job and a
      human at the CLI serialize instead of interleaving

**Status: DONE 2026-09-21** (`c0de85f`; backend 252/252, CI green). Migration
`20260921180000_season_lifecycle.sql` applied via `supabase db push`. What was built:
- `season_single_active` (unique index) and `season_period_check` (`end_at > start_at`).
- `transition_season(id, 'active'|'ended')` — legal moves upcoming → active, active → ended,
  upcoming → ended (cancel). **Activating a season ends the previous active one in the same
  transaction (rollover).** Ending the only active season on its own is **refused**.
- `advance_seasons(p_now)` — the automatic path: an active season past its `end_at` is ended
  and the earliest due `upcoming` one activated in one step; with no successor it is **left
  active and reported as `overrun`**; with no active season at all the earliest due upcoming
  one is activated; missed seasons are caught up one step at a time (bounded loop).
- pg_cron job `advance-seasons` hourly at :05 (a boundary is honoured within the hour) and
  `backend/scripts/season.ts` (`list | create | activate | cancel | advance`) for the
  admin-triggered path — both use the same functions, so they cannot disagree.
- Functions are `service_role`-only (`has_function_privilege` for `anon` is false, and the
  test calls them with the public anon key and is refused).

**Why "never zero active seasons" is a rule, not a nicety:** `POST /api/runs` cannot write
a ledger row without an active season (`lib/point-transaction.ts` throws), so a gap between
seasons would turn every run submission into a 500. The functions therefore never create one.
**Operational consequence:** `Season 1 — 2026` ends 2026-11-30 and no successor exists yet.
Until one is created (`season.ts create …`) the job reports `overrun` and Season 1 simply
stays active — nothing breaks, but the season never rolls. Create Season 2 before then.
The tests briefly move the real active season (that is what they test) and restore it exactly
afterwards — verified: production still has `Season 1 — 2026` active and no `T36-` leftovers.

---

### T3.7 — Season-scoped rank reset on transition

**Objective:** Implement the core season mechanic — competition resets,
lifetime progress doesn't.

**Scope:**
- Yang dikerjakan: on new season activation, the **global** `LeaderboardEntry`
  precompute (T2.18 — the only scope v1 computes) begins scoping fresh to
  the new `season_id`; explicit confirmation that
  `User.total_points`/`current_level` are untouched by the transition
  (product-spec AC 4.7.1). *(Changed 2026-09-21: previously depended on
  T3.2's per-region precompute, now deferred to Fase 4 — the dependency is
  re-pointed at T2.18, the job T3.2 would only have extended.)*
- Yang TIDAK dikerjakan: historical rank retention (T3.8 — separate
  concern); per-region scopes (deferred Local Leaderboard, T3.2 in
  phase-4-backlog.md — when that ships, its precompute inherits this
  season scoping).

**Depends on:** T3.6, T2.18

**Reference:** [product-spec.md](../../01-product/product-spec.md) AC 4.7.1

**Definition of Done:**
- [x] After a season transition, leaderboard rank starts fresh (verified:
      a top-ranked user in the old season is not automatically top-ranked
      in the new one just from carried-over lifetime points)
- [x] `User.total_points`/`current_level` unchanged across the transition

**DONE 2026-09-21** (commit `68842af`; migration
`20260921190000_season_rollover_leaderboard.sql`, applied to production).
Evidence: `lib/season-rank-reset.integration.test.ts` (5 tests, real Supabase,
real season moved and restored; production left with Season 1 active, 0 test
rows). Champion (lifetime 500) absent from the new season's board; a user with
lifetime 160 (100 old + 60 new, via the real ledger writer) is #1 with 60;
`user.total_points`/`current_level` identical before/after; old season's
standings untouched; flagged run resolved after the change compensates in the
ORIGINAL season; `GET /api/leaderboard` right after a transition returns the new
`season_id`, empty entries, `me: null`, `computed_at` set.
Honest note: the core mechanic already held by construction (per-season ledger
scoping) — 2 of 5 tests passed before the migration. The migration closed two
timing gaps, shown by the 3 tests that failed on the T3.6 functions: (1) the
ended season lacked up to 15 min of points in its final standings (now rebuilt
right before ending); (2) the new season had no `leaderboard_scope` row, so
`computed_at` was null until the next cron run (now rebuilt on activation).
Side effect: transitions now write `leaderboard_scope` rows, so the T3.6 test
cleanup also deletes them.

---

### T3.7a — Season League derivation (out-of-band, added 2026-09-21)

**Objective:** Make "tier" real. The Premium leaderboard AC (product-spec.md
§4.5 AC4) gated Freemium/Premium on a "tier" nobody had defined; it now means
**Season League** — Bronze / Silver / Gold / Platinum, derived from points
earned *during the current season* and reset every season (tech-spec.md §2.5).
This task builds the derivation and exposes the caller's own league. It is
Season-system groundwork, so it belongs here, not in the Premium tier.

**Scope:**
- Yang dikerjakan: `backend/lib/season-league.ts` — pure `leagueFor(seasonPoints)`
  over an exported `LEAGUE_BANDS` config (tech-spec.md §2.5 table, half-open
  `[min, max)`), plus a `season_points` read for one user/season that is the
  **same quantity** as `LEADERBOARD_ENTRY.points` for the global scope
  (validated/approved runs only, compensating ledger rows included). Expose the
  caller's `me: { season_points, league }` on `GET /api/seasons/active`
  (additive field — existing clients keep decoding). Document the shape in
  database-api-spec.md §2.5.
- Yang TIDAK dikerjakan: filtering the leaderboard by league and the
  Freemium-vs-Premium gating (both wait for the Premium tier, Fase 4);
  any client UI (T3.9 may choose to show it, not required here); a stored
  league column (it is derived from the ledger by design — no state to drift).
  No client-side copy of the function, so no fixture-parity file (ADR-0007
  applies only to formulas duplicated across Swift and TypeScript).

**Depends on:** T2.12c, T2.18, T3.7

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.5,
[product-spec.md](../../01-product/product-spec.md) §4.5 AC4

**Definition of Done:**
- [x] `leagueFor` is correct at every band boundary — 0, 79, 80, 249, 250, 599,
      600 and a very large value — and bands are config, not inline literals
- [x] `season_points` equals the user's `leaderboard_entry.points` for the same
      season, checked against real ledger rows (including a `flagged` run that
      is excluded until resolved and a compensated `rejected` one)
- [x] `GET /api/seasons/active` returns `me.season_points` / `me.league`,
      verified live with a real Auth JWT; 401 unchanged when unauthenticated
- [x] After a season transition (T3.6/T3.7) the league is computed from the new
      season only — a user who was Platinum last season is Bronze at 0 points
- [x] The band values are recorded as a starting point to be recalibrated with
      real data (tech-spec.md §2.5) — not presented as final

**DONE 2026-09-21.** Files: `lib/season-league.ts` (+ unit test, 8 boundary cases
incl. 0/79/80/249/250/599/600/1,000,000), migration
`20260921200000_season_points_function.sql` (`season_points(user, season)`,
service_role only, applied to production), `app/api/seasons/active/route.ts`
(`me`). Evidence: `lib/season-league.integration.test.ts` (5 tests, real
Supabase + real Auth JWT): `season_points` = `leaderboard_entry.points` = 120 with
validated 100 + approved 20 counted, flagged 40 held, rejected 30 netted to 0 by
its compensating row; live route returns `me {300, gold}`, 401 without a JWT,
`me: null` for a signed-in caller with no profile (season still 200); after a real
transition a 700-point `platinum` user is `0` / `bronze` in the new season with
old-season points untouched; anon key cannot call the function. Decisions to
know: league values are lowercase machine names (`gold`), matching the planned API
shape; `season_points` is deliberately NOT trust-filtered (that hides a user from the
public board only); `me` degrades to `null` rather than failing the season call.
Not verified: no client reads `me` yet (T3.9 may). Bands remain uncalibrated
starting values.

---

### T3.8 — Historical final rank retention after season ends

**Objective:** Let users see how they placed in past seasons, per
product-spec AC 4.7.3.

**Scope:**
- Yang dikerjakan: on season end, snapshot the final `LeaderboardEntry`
  state for that `season_id` (already immutable by construction since new
  precompute writes target the new season — this task adds a retrieval
  path/endpoint or screen for past-season results).
- Yang TIDAK dikerjakan: any UI beyond a simple past-seasons list/detail
  view.

**Depends on:** T3.7, T3.7a

**Reference:** [product-spec.md](../../01-product/product-spec.md) AC 4.7.3

**Definition of Done:**
- [x] A user's final rank from a completed season remains queryable after
      the season ends
- [x] Data is not overwritten or lost when a new season's precompute job
      runs
- [x] The user's final **league** (tech-spec.md §2.5) of a completed season is
      retained and retrievable alongside the final rank (added 2026-09-21 with T3.7a)

**DONE 2026-09-22.** Migration `20260922100000_season_results.sql` (applied to
production): `season_result` (written once, `on conflict do nothing`, never
updated), `league_band` (bands in the DB), `freeze_season_results()`, and
`transition_season`/`advance_seasons` now freeze the season they end, right after
its closing rebuild. New endpoint `GET /api/seasons/history` (caller's finished
seasons, newest first: `season_id, name, start_at, end_at, final_rank,
final_points, league, participants`; rate rule `seasons.history`).
Evidence: `lib/season-results.integration.test.ts` (7 tests, real Supabase + real
Auth JWT; all 6 DB-dependent ones failed before the migration): freeze on
`transition_season` AND on the hourly `advance_seasons`, ranks 1/2/3 with leagues
platinum/silver/bronze, points added after the last rebuild included; later
rebuilds/transitions and a second freeze leave results untouched; recalibrating
`league_band` does not change a past season's stored league; live route returns
the caller's season, `[]` for a user with none, 401 without JWT; anon key cannot
read either table or call the function.
Decisions to know: (1) the final league is STORED (not re-derived), because the
bands are meant to be recalibrated and re-deriving would rewrite history; the
price is two copies of the bands (`league_band` for the freeze in SQL,
`LEAGUE_BANDS` in TS for live `me.league`) — a parity test fails if they differ, so
changing a band means changing both. (2) A user not on the board when a season
closed (no counted points, or hidden by the trust filter) has no row. (3) Seasons
that ended before this migration have no results (none existed with data).
Not verified: no client screen reads history yet (product-spec AC 4.7.3 says
"queryable" — the client list/detail is T3.9's neighbour, not built).

---

### T3.9 — Season info screen with countdown

**Objective:** Surface season timing to users (product-spec AC 4.7.2).

**Scope:**
- Yang dikerjakan: screen consuming `GET /api/seasons/active`, showing
  season name and `days_remaining` countdown.
- Yang TIDAK dikerjakan: past-season browsing (that's T3.8's concern).

**Depends on:** T3.6, T2.17

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §2.5

**Definition of Done:**
- [x] Countdown displays correctly and updates as time passes (not just
      on app open)
- [x] Screen reflects the currently active season correctly across a
      transition (T3.6)

**DONE 2026-09-22.** New DTOs (`ios/Laju/Services/Networking/SeasonDTOs.swift`:
`ActiveSeasonResponse`, `ActiveSeasonMe`), `APIClient.fetchActiveSeason(jwt:)`,
`SeasonInfoViewModel` (loads on `.task`, same success/failure contract as
`LeaderboardViewModel`), and `SeasonInfoView`/`SeasonInfoContent` (season name,
countdown card, `me` points/league card when present). Reached from a toolbar
button on `LeaderboardView` (calendar icon) — no tab of its own, per
`RootTabView.swift`'s existing "unreachable-by-construction" note.
Countdown: server's `days_remaining` (`Math.ceil`, database-api-spec.md §2.5) is
shown right after load; between loads a `TimelineView(.periodic(from:by: 60))`
recomputes it every minute from `endAt` via `liveDaysRemaining(now:)`, using the
same `ceil` rule, so the two never disagree and the number moves without a
network call per tick.
Transition (T3.6): the screen has no state of its own for "which season" — every
`load()` re-fetches whichever row the server has `status='active'` and replaces
it wholesale, so a transition is reflected on the next load/refresh, same as
`LeaderboardView`. `transition_season`/`advance_seasons` switching the active row
is already covered by `season-lifecycle.integration.test.ts`; not re-tested
client-side beyond decoding a live-shaped response.
Evidence: `ios/LajuTests/SeasonInfoTests.swift` (10 tests: live-shaped decode
incl. `me`, bearer header + URL, null `me`, load success/failure/recovery,
signed-out short-circuits before any network call, countdown math at
day-boundary and past-end floors to 0, nil before first load, rendered content
snapshot). Full iOS suite green: 186/186.
### T3.10 — End-to-end verification: season close/open cycle (phase DoD gate)

**Objective:** Verify the actual acceptance bar from development-plan.md
Fase 3 before considering this phase done.

**Scope:**
- Yang dikerjakan: simulate closing an active season and opening a new
  one in a test environment; confirm lifetime stats intact, the **global**
  leaderboard recomputes correctly for the new season, historical final
  rank remains viewable. *(Changed 2026-09-21: previously "all three
  regional leaderboard scopes"; the regional scopes are deferred to Fase 4
  with the Local Leaderboard.)*
- Yang TIDAK dikerjakan: any new functionality — verification only, bugs
  found route back to T3.1 and T3.6–T3.9.

**Depends on:** T3.1, T3.7, T3.7a, T3.8, T3.9 *(T3.5 removed 2026-09-21 — the Local
Leaderboard screen is deferred; nothing else about the gate changes)*

`T3.9` added 2026-09-17: it was previously absent from this gate, which
meant nothing depended on the Season Info screen at all and Fase 3 could
be signed off with it unbuilt. AC 4.7.2 (time remaining visible) and
AC 4.7.3 (final rank viewable after a season ends) both land on T3.9, and
both are Must-have — so the gate cannot be honest without it.

**Reference:** [development-plan.md](../development-plan.md) Fase 3 DoD

**Definition of Done:**
- [x] Full season close→open cycle tested with seeded multi-user data
      on the global leaderboard (regional scopes deferred, see phase-4-backlog.md)
- [x] Lifetime `User.total_points`/`current_level` verified unchanged
      post-transition
- [x] Season league (T3.7a) resets with the season: computed from the new
      season's points only (added 2026-09-21)
- [x] Previous season's final rank still retrievable after transition
- [x] Season Info screen (T3.9) verified working against a real season —
      countdown correct (AC 4.7.2) and a past season's final rank still
      viewable after the transition above (AC 4.7.3)
- [x] **Every row in [deferred-manual-tests.md](../../04-quality-security/deferred-manual-tests.md)
      belonging to a Fase-3 task is either Pass, or explicitly documented
      as an accepted limitation** (the pattern T0.9's battery item and
      T1.17 already set) — this gate cannot be signed off with a deferred
      test silently still outstanding (added 2026-09-17)
- [x] Sign-off recorded before considering Phase 3 complete

**DONE 2026-09-22 — Phase 3 sign-off.** Verification only, per this task's own
scope; no functional bug required routing back to T3.1/T3.6–T3.9.

New composite test: `backend/lib/season-e2e-cycle.integration.test.ts` (1 test,
real Supabase, seeded with 3 users — gold/mid/runner — through the real
`recordRunPointsAndUpdateAggregate` writer, not a raw ledger insert, so lifetime
stats are genuinely non-zero before the transition). One scenario ties together
what T3.6–T3.9's own integration tests each prove in isolation, so a boundary
bug between them has nowhere to hide:
- Season A active, 3 users score 700/200/50 → board ranks 1/2/3 correctly.
- Season A closed, season B opened (`transition_season`).
- **Lifetime stats untouched:** all 3 users' `total_points`/`current_level`
  identical before and after the transition.
- **Global leaderboard recomputes for the new season:** B starts at `[]`
  (nothing carried over — A's champion earns 0 in B and is simply absent, not
  zeroed), then a NEW ranking forms from B-only runs.
- **Season league resets (T3.7a):** the same user's `season_points()` differs
  per season on the SAME call — gold is platinum in A, bronze in B (0 points
  there); runner is platinum in B on B's points alone.
- **Historical final rank retrievable (T3.8):** `season_result` for season A
  is correct after B is active, both directly and through the real
  `GET /api/seasons/history` route with a real Auth JWT.
- **`GET /api/seasons/active` (T3.9's data source) reflects the new season:**
  correct `id`, `me` scoped to B's points only (not A's), correct
  `days_remaining`.

Full backend suite: 291/291 passing, `tsc --noEmit` clean, eslint clean.

**Season Info screen (T3.9) verified against a real season:** hit the LIVE
deployed backend (`https://backend-eight-gules-56.vercel.app`, not just an
in-process route call) with a real Auth JWT (magic-link session, project is
Apple/Google-only per `test-support/auth.ts`) —
`GET /api/seasons/active` → `200`, real Season 1 — 2026, `days_remaining: 70`
(2026-09-22 → 2026-11-30, correct), confirming AC 4.7.2's data source is live
and correct. `GET /api/seasons/history` → `401 profile_missing` for a
profile-less identity — the correct gate (`requireUser`'s contract), not a bug.
AC 4.7.3 (past season's final rank viewable) is proven end-to-end by the
composite test above (`season_result` + the live route logic, both exercised);
the iOS screen's own rendering of that data was already unit-verified in T3.9
(`SeasonInfoTests.swift`, 10/10, incl. a rendered content snapshot) — not
re-run against the physical device here, same scope boundary as every other
non-hardware DoD item in this repo.

**T3.1 found unchecked and closed out** (see its own DONE note above) — its
functionality had already shipped, only the checklist was stale; this gate is
exactly what caught it.

**deferred-manual-tests.md:** zero rows tagged to any Fase-3 task (T3.1–T3.9) —
checked directly, nothing to action. Vacuously satisfies this gate's DoD item.

**Sign-off: Phase 3 (Season System) is DONE.** All of T3.1, T3.6, T3.7, T3.7a,
T3.8, T3.9, T3.10 are complete; T3.2–T3.5 formally moved to Fase 4
(`phase-4-backlog.md`) on 2026-09-21, so nothing in this phase file remains open.

