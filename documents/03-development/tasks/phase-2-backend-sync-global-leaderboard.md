# Phase 2 — Backend + Sync + Global Leaderboard

Source: [development-plan.md](../development-plan.md) Fase 2

**Hard dependency for this whole phase:** anti-cheat, including its
fixture corpus, orchestration/ledger, and resolution lifecycle (T2.6b,
T2.7–T2.11, T2.12a–T2.12f, T2.13), must ship and be verified **before**
the global leaderboard is made publicly visible (T2.20–T2.21). This is a
correctness requirement, not a nice-to-have — see development-plan.md
Fase 2.

---

### T2.0a — Navigation shell (`TabView` root)

**Objective:** Give the app a tab-based root so the screens this phase and
Fase 3 build are reachable at all.

**Numbered `T2.0a` deliberately** (2026-09-17): inserting a `T2.1` and
renumbering would have invalidated 25+ existing cross-references across
the spec set for no benefit. A new out-of-band ID placed first in the file
follows the same precedent as the `T2.12a`/`T2.14b` sub-IDs already in use
here, and `T0.5`'s removal-without-renumber in Fase 0.

**Why this is first in the phase:** T2.20 (global leaderboard), T3.5
(local leaderboard — CANCELLED PERMANENTLY 2026-09-22, was deferred since 2026-09-21; the screen-scaffolding argument
still holds for it) and T3.9 (season info) each build a screen with no
entry point. Before this task, `RunTrackingView` was the app root with
floating overlay buttons pushing to History and Profile — a structure with
nowhere to add a fourth or fifth destination. All three screens were
unreachable-by-construction; an audit found that no task owned fixing it.

**Scope:**
- Yang dikerjakan: `RootTabView` as the new root (replacing
  `RunTrackingView` in `LajuApp`), with exactly two tabs — **Track**
  (`RunTrackingView`) and **You** (`ProfileView`). A `LajuTab` enum holds
  tab identity (title + SF Symbol) so a future tab is an enum case plus one
  `tabItem` block, not a restructure. Removal of the now-duplicate
  `profileButton` overlay from the Track screen.
- Yang TIDAK dikerjakan: **any tab without real content behind it.** A
  Social tab lands with T2.20's leaderboard; a Circle tab only if the
  Fase-4 Circle feature (T4.1) is promoted into scope, which is not
  decided. An empty or disabled placeholder tab is worse than an absent
  one and is explicitly not built here. Also not in scope: moving Run
  History out of its Track-screen overlay — Profile shows only the 5 most
  recent runs, so that overlay stays the route to the full list.

**Depends on:** T1.6 (ProfileView must exist to be the "You" tab's content)

**Reference:** [screen-inventory.md](../../06-design/screen-inventory.md) §5
(navigation shell), [design-notes.md](../../06-design/design-notes.md) §0
(forced dark), [product-spec.md](../../01-product/product-spec.md) §4.5/§4.6/§4.7
(the screens this unblocks)

**Definition of Done:**
- [x] `RootTabView` is the app root after onboarding; `LajuApp` no longer
      presents `RunTrackingView` directly — verified on simulator
      (iPhone 17 Pro, iOS 26.3): tab bar renders with Track and You, and
      switching between them preserves each tab's own state
- [x] Exactly two tabs are rendered — no empty or placeholder tab
- [x] Adding a third tab requires only a new `LajuTab` case and one
      `tabItem` block, with no change to `RootTabView`'s body structure
- [x] `profileButton` removed from the Track overlay (Profile is now a
      tab, so the overlay was a second route to the same destination);
      `historyButton` retained
- [x] Tab bar renders dark regardless of the device's Light/Dark Mode
      setting — inherited from `LajuApp`'s window-level
      `.preferredColorScheme(.dark)` (design-notes.md §0)
- [x] Build clean under Swift 6 strict concurrency, warnings-as-errors
- [ ] Verified on a **physical device** (iOS 18.x) — the simulator run
      showed a rendering artifact on iOS 26.3 (the two tab icons also
      drawn in the status-bar area on the You tab, which has a
      `NavigationStack`). Not reproducible on the deployment target from
      this machine: only the iOS 26.3 runtime is installed. Tracked in
      [deferred-manual-tests.md](../../04-quality-security/deferred-manual-tests.md)

---

### T2.1 — Provision Supabase project + Next.js backend skeleton on Vercel

**Objective:** Stand up the infrastructure everything else in this phase
runs on.

**Scope:**
- Yang dikerjakan: create Supabase project (Postgres + Auth), init
  `backend/` as Next.js (App Router) + TypeScript, connect DB client,
  deploy an empty health-check route to Vercel.
- Yang TIDAK dikerjakan: any schema, any business logic, any auth flow.

**Depends on:** None

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §1

**Definition of Done:**
- [x] `GET /api/health` deployed and reachable on Vercel — verified
      2026-09-17: `curl https://backend-eight-gules-56.vercel.app/api/health`
      → `{"status":"ok"}`, HTTP 200, from the public internet (not just
      `vercel dev`/localhost)
- [x] Supabase project connected, credentials stored as env vars (not
      committed) — Supabase project `laju` (ref `qfjavbrwhfjkjremtvol`,
      region `ap-southeast-1`) created under the existing account's
      `FORM___INT` org; `NEXT_PUBLIC_SUPABASE_URL` and
      `NEXT_PUBLIC_SUPABASE_ANON_KEY` stored as Vercel `Config` vars (anon
      key is meant to be public, protected by RLS — Supabase's own model),
      `SUPABASE_SERVICE_ROLE_KEY` stored as a Vercel `Secret` (never
      exposed, per database-api-spec.md §2.1b's rule that this key must
      never reach anything but the backend). Locally, `backend/.env.local`
      holds the same three plus `DATABASE_URL` for T2.2's migrations —
      confirmed gitignored (`git check-ignore` verified), never committed.
      Connection verified live: `curl .../rest/v1/` with the `service_role`
      key returned the project's real PostgREST OpenAPI spec, HTTP 200 —
      not just "the env var is set," the database is actually reachable

---

### T2.2 — Migrate core DB schema (User, Run, PointTransaction, Season, LeaderboardEntry, LeaderboardScope)

**Objective:** Create the tables everything in this phase writes to.

**Scope:**
- Yang dikerjakan: SQL migrations for all 6 core entities per the ERD —
  User, Run, PointTransaction, Season, LeaderboardEntry, and
  **LeaderboardScope** (migrated here, not Fase 3, since the global
  leaderboard needs an explicit `scope_type='global'` row from Fase 2
  onward — database-api-spec.md §1) — including the reserved `club_id`
  nullable FK on `User` (unused, forward compat only).
- Yang TIDAK dikerjakan: the `Club` table itself (explicitly Won't/backlog
  per product-spec.md), any seed data beyond what's needed for later
  tasks.

**Depends on:** T2.1

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §1 (ERD)

**Definition of Done:**
- [x] All 6 tables exist in Supabase with fields/types matching the ERD —
      verified 2026-09-17 via `psql "$DATABASE_URL" -c "select table_name
      from information_schema.tables where table_schema='public'"` against
      the live remote project: exactly `leaderboard_entry`,
      `leaderboard_scope`, `point_transaction`, `run`, `season`, `user`
- [x] Migrations are version-controlled and re-runnable (not manual
      console edits) — `backend/supabase/migrations/20260917162813_create_core_schema.sql`,
      applied via `supabase db push` (not the dashboard SQL editor)
- [x] `User.club_id` present and nullable, no `Club` table created —
      verified: `\d "user"` shows `club_id uuid` with no `NOT NULL`, no FK
      constraint listed; `select to_regclass('public.club')` returned null
- [x] `LeaderboardScope` supports a `scope_type='global'` row using
      sentinel `scope_id='GLOBAL'` (NOT NULL) — composite PK
      `(season_id, scope_type, scope_id)` is valid since no column is
      nullable (database-api-spec.md §1) — verified functionally: inserted
      a real `('...', 'global', 'GLOBAL', ...)` row against a live PK,
      read it back, not just confirmed the DDL allows it in theory
- [x] `Run.updated_at` column exists (`NOT NULL DEFAULT now()`),
      maintained by a **DB-level trigger** (not application code, so no
      writer path can forget it) on any change to
      `status`/`flag_confidence`/`final_points_awarded`/`resolved_at`;
      index on `(user_id, updated_at)` created — this is what
      `GET /api/runs?since=` (T2.14c) filters on. **Verified functionally,
      not just structurally**: seeded a run with `updated_at` forced to
      `2020-01-01`, updated `status` → `updated_at` jumped to the real
      current time; reset to `2020-01-01`, then updated the unrelated
      `distance_meters` column → `updated_at` stayed at `2020-01-01`. The
      trigger fires only for the specified columns, proven both ways, not
      assumed from the trigger definition alone
- [x] `User.deleted_at` (nullable) and `User.auth_user_id` present —
      `auth_user_id` deliberately separate from `User.id` (not a synonym),
      used only by `DELETE /api/account` (database-api-spec.md §1/§2.1b,
      T2.22) (added 2026-09-13, Round 7 finding N7-P13/B7-9). Verified:
      both columns present, `auth_user_id` has a `UNIQUE` constraint but
      **no FK to `auth.users`** (deliberate — see the migration file's own
      comment: a hard FK here would CASCADE or RESTRICT on Auth-identity
      deletion, defeating soft-delete either way)

---

### T2.3 — Supabase Auth integration (mobile sign up/in + backend JWT verification)

**Objective:** Give users a persistent identity across devices/sessions.

**Scope:**
- Yang dikerjakan: Supabase Auth Swift SDK wired into `ios/` (sign
  up/sign in SwiftUI screens, session persistence via Keychain), JWT
  verification middleware on `backend/` API routes — middleware also
  rejects any request where the caller's `User.deleted_at` is non-null
  (database-api-spec.md §3, added 2026-09-13 Round 7 finding B7-10), not
  just a missing/invalid JWT. Auth method decision recorded: if any
  third-party OAuth provider is offered alongside email/password, Sign in
  with Apple must ship alongside it (App Store Guideline 4.8,
  pre-launch-checklist.md §5) — resolve product-spec §4.1 AC1's
  "email/password atau OAuth" ambiguity as part of this decision, not
  after.
- Yang TIDAK dikerjakan: profile completion (region/username — T2.4),
  any custom backend-issued session tokens (auth is Supabase-native per
  tech-spec.md).

**Depends on:** T2.1, T0.2

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §1 (Auth row),
[database-api-spec.md](../../02-architecture/database-api-spec.md) §2 (Auth section), §3,
[pre-launch-checklist.md](../../04-quality-security/pre-launch-checklist.md) §5

**Definition of Done:**
- [ ] **User can sign up and sign in from the mobile app — BLOCKED, not by
      code.** `SupabaseConfig.swift`/`AuthService.swift`/
      `OnboardingSignInStep.swift` are written, compile cleanly, and link
      correctly against the Supabase Swift SDK (verified: full simulator
      build succeeds, all 89 existing tests still pass — zero regression
      from the SDK integration). The entitlement (`Laju.entitlements`,
      `com.apple.developer.applesignin`) is wired via `project.yml`. What's
      blocked: Apple requires a **paid Apple Developer Program
      membership** to provision the Sign in with Apple capability at all —
      confirmed live 2026-09-17, `xcodebuild` error: "Personal development
      teams, including 'Mochamad Arif Fahrizal', do not support the Sign
      In with Apple capability." Team `NTHHTF27HU` (used successfully for
      T0.4's plain device build, which needed no special capability) is a
      free Personal Team. This is an Apple account-tier restriction, not
      something any project configuration can route around. Tracked in
      [deferred-manual-tests.md](../../04-quality-security/deferred-manual-tests.md)
      pending Developer Program enrollment (user's decision, not made
      here — enrollment costs money and is the account holder's call)
- [x] Session persists across app restarts (product-spec AC 4.1.3) — by
      construction: `AuthService`'s `sessionStorage` is the Supabase SDK's
      default Keychain-backed storage, the same mechanism proven in
      `T2.3`'s Sign in with Apple flow doc research. Full round-trip
      verification (sign in → force-quit → relaunch → still signed in)
      is blocked by the same Developer Program gap as the item above,
      since it needs a completed sign-in first
- [x] A protected backend route rejects requests without a valid JWT
      (`401`, per database-api-spec.md §3) — verified live against the
      deployed `GET /api/auth/me`: no header → 401; garbage token → 401
- [x] A protected backend route rejects a request bearing a valid JWT for
      a soft-deleted account (`User.deleted_at` non-null) — needed for
      T2.22 to be effective. **Verified with a real, cryptographically
      valid Supabase session JWT** (not a mock): created a real Auth test
      user via the Admin API, signed in for a genuine access token,
      inserted a `user` row with `deleted_at` set, hit the deployed route
      with that real token → `401 "This account has been deleted"`.
      Cleared `deleted_at`, same token → `200` with the user's own row.
      Test identity and row deleted afterward
- [x] Auth provider decision recorded; if OAuth is offered, Sign in with
      Apple ships alongside it (Guideline 4.8) — if email/password only,
      recorded as not applicable. **Decided 2026-09-17: Sign in with
      Apple only** — no email/password, no other OAuth provider. Recorded
      in product-spec.md §4.1 AC1 and pre-launch-checklist.md §5 (closed).
      **Reversed 2026-09-21: Google Sign-In added as a second provider,
      alongside Apple** (not instead of it) — Android roadmap, and it needs no
      paid Apple entitlement so the real sign-in path can be tested; Guideline
      4.8 still satisfied because Apple stays. See product-spec.md §4.1 AC1,
      tech-spec.md §6, pre-launch-checklist.md §5
- [x] **Google sign-in round-trip verified live 2026-09-21:** real button → OAuth PKCE → Supabase session → authenticated
      sync/reconciliation/Profile/Ranks → force-quit → cold relaunch still signed in (evidence in the "Real
      client–server chain" block above). The **Apple** half of this task's round-trip remains unverified (needs the
      paid Apple Developer Program) — which is why T2.3 stays PARTIAL

---

### T2.4 — POST /api/profile/complete endpoint — **region half SUPERSEDED 2026-09-22**

> **Partially superseded 2026-09-22 (PM sign-off).** Decision D1 is reversed: region
> (kecamatan/kabupaten_kota/provinsi) is removed entirely from onboarding and the schema
> (product-spec.md §4.1, §4.6). This task's **"minimal region validation"** — all 3 region fields
> required, non-empty, `400` if any is missing — is therefore being removed, along with the region
> columns themselves (Task B: migration; Task C: endpoint rework). The rest of this task
> (username/display_name profile completion, the endpoint itself, its `profile_missing` 401 flow)
> is **unaffected and stays**. Everything below is the shipped implementation as built, kept as a
> historical record — the region assertions in its DoD no longer describe intended behavior.

**Objective:** Capture the region data leaderboard features depend on
later in this phase and in Fase 3.

**Scope:**
- Yang dikerjakan: endpoint per database-api-spec.md §2.1 (username,
  display_name, region fields), mobile onboarding screen calling it after
  first sign-in. **Minimal region validation**: all 3 region fields
  (kecamatan/kabupaten_kota/provinsi) required, non-empty strings —
  request rejected with `400` if any is missing. This is presence
  validation only (mirrors the Season pattern: minimal now, full
  richness later) — matching against a real administrative catalog is
  not v1 scope.
- Yang TIDAK dikerjakan: the client-side onboarding UX that blocks the
  run-start flow before submission — that's T3.1 in Fase 3; this task
  only captures + minimally validates the data. (The backend `409` guard
  on `POST /api/runs` itself is T2.5, not this task.)

**Depends on:** T2.2, T2.3

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §2.1

**Definition of Done:**
- [x] Endpoint creates/updates the `User` row with submitted fields,
      matches request/response shape in database-api-spec.md §2.1 —
      verified live 2026-09-17 with a real Supabase Auth identity (not a
      mock): a genuinely valid JWT for an identity with **no existing
      `user` row** correctly reached the validation logic (not a 401 —
      confirming `requireAuthenticatedIdentity` vs `requireUser`'s
      chicken-and-egg fix works), a full valid submission returned `201`
      with the exact `{id, username, total_points, current_level}` shape,
      the row was confirmed in Postgres with all fields correct via
      `psql`, and calling again with the same identity updated the same
      row (`upsert` on `auth_user_id`) rather than creating a duplicate —
      row count stayed at 1
- [x] Request rejected with `400` if any of the 3 region fields is
      missing or empty — verified live with the same real JWT
- [ ] **Mobile onboarding flow calls this after first sign-in — BLOCKED,
      by two separate things, neither of them this task's code.** (1)
      Same Apple Developer Program gap as T2.3 — there is no completed
      sign-in to call this after, on this machine, yet. (2) **No
      region-collection UI exists in onboarding to source the call's
      data from** — `OnboardingContainerView`'s four steps (welcome,
      coreLoop, signIn, permission) do not include one, and building one
      now would be scope creep: T2.4's own Scope explicitly excludes "the
      client-side onboarding UX that blocks the run-start flow" as T3.1's
      job (Fase 3), not this task's. This DoD item cannot be closed
      before T3.1 lands, regardless of the Developer Program status —
      recorded here so it isn't mistaken for solely an auth blocker

---

### T2.5 — POST /api/runs endpoint — ingestion only (no calc/anti-cheat yet) — **region `409` guard SUPERSEDED 2026-09-22**

> **Partially superseded 2026-09-22 (PM sign-off).** This task's **"basic region guard"** — `409
> Conflict` if the submitting user has no region set — is being removed with the region columns
> themselves (D1 reversed; product-spec.md §4.1). Task C replaces it: leaderboard *visibility* is
> gated on granted location permission (§4.5 AC5) rather than run *submission* being gated on
> region. Note the shape change: the old guard blocked submitting a run; the replacement does not —
> it only gates what the user can see. Everything else in this task is unaffected. Text below is the
> shipped implementation, kept as a historical record.

**Objective:** Get a run payload from device to database, as a foundation
to build validation on top of.

**Scope:**
- Yang dikerjakan: endpoint accepts the run payload shape from
  database-api-spec.md §2.2 (`gps_route` as an array of
  `{lat, lng, timestamp, elevation}` points), writes a `Run` row with a
  placeholder `status = validated` (no real validation logic yet —
  T2.12a adds the actual `validated|flagged|rejected` determination per
  tech-spec.md §2.4.1), returns a stub response. **Basic region guard**:
  returns `409 Conflict` if the submitting user has no region set at all
  (presence check only — matches database-api-spec.md §3; the richer
  client-side onboarding block is T3.1 in Fase 3, not this task).
- Yang TIDAK dikerjakan: point calculation, anti-cheat, `PointTransaction`
  writes — all explicitly deferred to T2.12a and later.

**Depends on:** T2.2, T2.3, T2.4

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §2.2, §3

**Definition of Done:**
- [x] A run payload posted from a REST client creates a `Run` row with
      correct fields — verified live 2026-09-17 with a real Supabase Auth
      identity: `201` response matched database-api-spec.md §2.2's exact
      shape (`run_id`, `status: "validated"`, `flag_confidence: null`,
      `final_points_awarded: 0` — placeholder, real calc is T2.6/T2.12a,
      `anomaly_flags: []`), and the row was confirmed in Postgres via
      `psql`: `distance_meters=5230`, `duration_seconds=1930`,
      `avg_pace_sec_per_km=369` (arithmetically consistent, 369×5.23≈1930),
      2 GPS points stored
- [x] Endpoint requires valid auth (rejects unauthenticated requests) —
      verified live: no header → `401`
- [x] `409 Conflict` returned for a run submitted by a user with no
      region set — verified live with a real user row that had a
      username but no region fields
- [x] `422` returned for a `gps_route` point missing `timestamp` or
      `elevation` — verified live with a point missing `elevation`
- [x] `400` returned for zero/negative `distance_meters` or
      `duration_seconds` (database-api-spec.md §3) — verified live with
      `distance_meters: 0`
- [x] **Bonus verification, not a listed DoD item but load-bearing**: a
      valid JWT for an identity with **no `user` row at all** correctly
      gets `401` from `requireUser` (not `409` — confirms this endpoint
      is correctly using the stricter auth helper, unlike T2.4)

---

### T2.6 — Server-side point calculation module (fixture-parity with client formula)

**Objective:** Compute authoritative points server-side, using the exact
same formula as the offline client (Fase 1) — not a reimplementation.

**Scope:**
- Yang dikerjakan: `backend/lib/point-calculation.ts` — a TypeScript
  reimplementation of `calculatePoints` (T1.1's Swift function cannot be
  literally imported cross-language post-pivot; parity is enforced via
  the shared fixture file instead, tech-spec.md §2.2b), using the
  submitted `distance_meters`/`duration_seconds` top-level fields directly
  (same values the client used for its optimistic estimate) — **not**
  derived from `gps_route`. `gps_route`'s per-point detail is not read by
  this module at all; it exists solely for the anti-cheat checks
  (T2.7–T2.10) to do per-segment analysis. Keeping this module decoupled
  from `gps_route`'s shape is what makes it trivially identical to T1.1's
  client-side function.
- Yang TIDAK dikerjakan: any anti-cheat filtering of the route data — this
  task computes points assuming the run is clean; T2.7–T2.10 add the
  filtering, T2.12a applies it to the aggregate result.

**Depends on:** T1.1, T2.5

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.2, §2.2b

**Definition of Done:**
- [x] Given identical input, this module and the mobile T1.1 function
      produce identical point output — verified via both sides' unit
      tests passing against `shared/point-formula.fixtures.json`
      (tech-spec.md §2.2b), not via a literal shared import.
      `backend/lib/point-calculation.ts` reads the same 16-row fixture
      file T1.1's Swift tests already used, via `it.each`, not
      hand-duplicated values — all 16 pass (`npm test`,
      `lib/point-calculation.test.ts`)
- [x] Parity test fails if `shared/point-formula.fixtures.json` is empty
      (row-count assertion) — same requirement as T1.1's, so neither side
      can pass this DoD against a vacuous fixture. Present as its own
      test (`"the fixture file is non-empty"`), independent of the
      per-row `it.each` tests
- [x] No formula constants hand-duplicated without also updating
      `shared/point-formula.fixtures.json` (repo-coding-rules.md §4 PR
      checklist) — `STREAK_BONUS_PER_DAY`, `STREAK_CAP_DAYS`,
      `MIN_DISTANCE_KM_FOR_POINTS` in `point-calculation.ts` match
      `PointFormula.swift`'s values exactly (2, 7, 0.1), with the same
      rationale comments (ADR-0009's 5× stationary-radius reasoning)
      carried over, not just the numbers

---

### T2.6b — Build GPS test fixture corpus (spoofed vs. real)

**Objective:** Provide the anti-cheat checks (T2.7–T2.10) and their
verification (T2.13) with a shared, versioned dataset up front — so each
check is tested against data nobody on the implementing side authored
for their own check, and so the corpus exists before it's needed instead
of being built retroactively inside T2.13 (an earlier audit round found
anti-cheat checks being verified only against ad-hoc data the implementer
wrote themselves — this task exists specifically to close that gap).

**Scope:**
- Yang dikerjakan: collect 3–5 genuine GPS routes (can reuse recordings
  from T0.9's field testing), plus synthetic mutations covering each
  tech-spec.md §2.4 case (pace cap breach, GPS speed jump, teleport,
  elevation anomaly, combined cases) and clean negative-control routes;
  fixtures use the current `gps_route` point format
  (`{lat, lng, timestamp, elevation}` per point, database-api-spec.md
  §1/§2.2 — not the old 2D-only format); checked into the repo as a
  versioned fixture format (e.g. JSON files under a `fixtures/gps-routes/`
  directory) consumable by both T2.7–T2.10 and T2.13.
- Yang TIDAK dikerjakan: running the anti-cheat checks against the
  fixtures (that's T2.7–T2.10 and T2.13) — this task only produces the
  data.

**Depends on:** T2.5

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.4

**Definition of Done:**
- [x] Fixture corpus checked into the repo with a documented format —
      `backend/fixtures/gps-routes/`, format and rationale documented in
      that directory's own `README.md`
- [x] Covers every case in tech-spec.md §2.4 (pace cap, GPS speed jump,
      teleport, elevation anomaly, combined) plus clean/normal negative
      controls — 7 fixtures, one per case plus 2 clean controls (one
      comfortably clear of every threshold, one deliberately close to the
      pace cap to catch an over-aggressive check). **Every fixture
      independently verified 2026-09-17** against its claimed metric using
      Haversine distance (not the generator script's own flat-earth
      approximation, to catch a systematic error) — each crosses its
      intended threshold and, where relevant, does not also cross an
      unrelated one (`pace-cap-breach` peaks at 24.0 km/h, under the 25
      km/h speed-jump cap; `teleport` sustains only 1 sample over 25 km/h,
      not the >3 the speed-jump check requires)
- [ ] **At least 3 fixtures are genuine recorded routes — BLOCKED, not
      fabricated.** Zero prior on-device run data (T0.8, T0.9, the 24km
      calibration run pk=81, or any other field test) was ever exported
      to a file in this repo — always pulled ad-hoc from a device's local
      Core Data store during the session that needed it, never committed.
      The connected physical device (`Ripo Gagah`, iPhone 13) went
      `unavailable` (`xcrun devicectl list devices`, disconnected)
      partway through this task and stayed that way on recheck. A
      synthetic route mislabeled "genuine" would defeat the entire
      purpose of this requirement — real-world GPS noise no synthetic
      construction substitutes for — so this is reported open rather than
      worked around. Documented in
      `backend/fixtures/gps-routes/README.md`'s own "Genuine routes"
      section with exactly what's needed to close it (reconnect + pull
      historical data, or record ≥3 fresh real routes); tracked in
      [documents/README.md](../../README.md) §3

---

### T2.7 — Anti-cheat check: pace cap

**Objective:** Implement the first anti-cheat rule — the most common
false signal (GPS noise vs. genuine cheating) needs to be right.

**Scope:**
- Yang dikerjakan: segment-level check per tech-spec.md §2.4 — pace
  faster than 3:00/km sustained over >1km excludes that segment from
  point calculation and sets an `anomaly_flags` entry.
- Yang TIDAK dikerjakan: the other three checks (T2.8–T2.10), trust score
  aggregation (T2.11).

**Depends on:** T2.6, T2.6b

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.4 (Pace cap row)

**Definition of Done:**
- [x] Synthetic route with a >1km segment faster than 3:00/km triggers
      exclusion of that segment and the correct flag string —
      `backend/lib/anti-cheat/pace-cap.ts`, tested against T2.6b's real
      `pace-cap-breach.json` fixture (not a hand-rolled test route):
      returns `anomalyFlags: ["pace_cap_exceeded"]` and non-empty excluded
      segment indices
- [x] Normal-pace routes are unaffected (no false positive on the happy
      path) — verified against **both** clean-control fixtures, including
      the one deliberately paced close to the 3:00/km boundary (4:30/km),
      not just an easy jog far from it. Also verified the check does not
      cross-trigger on the isolated `gps-speed-jump` fixture, and — using
      `combined-anomalies` — that it does not reach into a route's
      GPS-speed-jump-only tail beyond the sliding window's legitimate
      1km-reach boundary crossing

---

### T2.8 — Anti-cheat check: GPS speed jump detection

**Objective:** Catch teleportation-style GPS anomalies within a run.

**Scope:**
- Yang dikerjakan: per tech-spec.md §2.4 — instantaneous speed (computed
  from each point pair's `lat`/`lng`/`timestamp`) >25 km/h sustained
  across >3 consecutive samples excludes that segment.
- Yang TIDAK dikerjakan: the other checks, trust score, and **status
  determination** — whether the run ends up `validated`/`flagged`/
  `rejected` is decided once, in aggregate, by T2.12a using
  `FLAG_THRESHOLD_PCT`/`REJECT_THRESHOLD_PCT` (tech-spec.md §2.4.1). This
  task only excludes segments and records `anomaly_flags` — it must not
  invent its own threshold.

**Depends on:** T2.6, T2.6b

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.4 (GPS speed jump row),
§2.4.1 (status determination — single source of truth, owned by T2.12a)

**Definition of Done:**
- [x] Synthetic route with a sustained >25km/h jump triggers segment
      exclusion and the correct `anomaly_flags` entry —
      `backend/lib/anti-cheat/gps-speed-jump.ts`, tested against T2.6b's
      real `gps-speed-jump.json` fixture; flags follow
      database-api-spec.md §2.2's own literal example naming
      (`gps_speed_jump_segment_N`, per-segment, not the flat string
      pace-cap uses — that distinction is the spec's own precedent)
- [x] Normal routes unaffected — verified against both clean-control
      fixtures. Also verified two deliberate non-obvious boundaries: (1)
      does not cross-trigger on `pace-cap-breach` (peaks at exactly 24.0
      km/h, just under this check's 25 km/h cap), and (2) does **not**
      trigger on `teleport`'s ~3596 km/h single-sample spike, since it
      isn't sustained past >3 consecutive samples — confirming the
      deliberate split with T2.9's distance/duration-sanity check rather
      than the two checks silently overlapping
- [x] This task's DoD does not assert any run `status` outcome — that
      belongs to T2.12a's boundary tests. Confirmed: this module's return
      type carries only excluded segments and flags, no status field

---

### T2.9 — Anti-cheat check: distance/duration sanity (teleport detection)

**Objective:** Catch cases where total distance/duration doesn't add up
plausibly, even without a clear single-segment jump.

**Scope:**
- Yang dikerjakan: per tech-spec.md §2.4 — exclude segments where overall
  distance/duration ratio is inconsistent with the recorded GPS points
  (large location jump within a short interval, using per-point
  `timestamp`). Note: a legitimate pause (T1.2b) produces a real time
  gap with **no** intermediate points and no location jump — by
  construction (GPS logging is stopped during pause, not filtered) this
  check should not trigger on a paused-then-resumed run; no special-case
  handling is needed here, but this is called out so a future
  implementer doesn't add one unnecessarily.
- Yang TIDAK dikerjakan: the other checks, trust score, and **status
  determination** — same rule as T2.8: this task excludes segments and
  sets `anomaly_flags`; the aggregate `validated`/`flagged`/`rejected`
  decision belongs solely to T2.12a (tech-spec.md §2.4.1).

**Depends on:** T2.6, T2.6b

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.4 (Distance/duration
sanity row), §2.4.1 (status determination — single source of truth,
owned by T2.12a)

**Definition of Done:**
- [x] Synthetic route with an implausible location jump excludes the
      correct segment and adds the correct `anomaly_flags` entry —
      `backend/lib/anti-cheat/distance-duration-sanity.ts`, tested
      against T2.6b's real `teleport.json` fixture. **Threshold
      (`IMPLAUSIBLE_JUMP_SPEED_KMH = 150`) is a documented starting
      value, not a spec-given number** — tech-spec.md §2.4's row for this
      check is qualitative ("GPS loncat lokasi jauh dalam interval
      pendek"), unlike pace cap and speed jump which both have explicit
      numbers. Flagged in the code with the same "pending real-run-data
      calibration" status as `MIN_DISTANCE_KM_FOR_POINTS`/pace-bracket
      table, not silently presented as final. Also verified: does not
      cross-trigger on `gps-speed-jump.json` (sustained ~40km/h, well
      under this check's 150km/h single-segment threshold), and does not
      trigger across a genuine pause gap (constructed inline: a real
      10-minute time gap with no location jump — confirming the Scope
      note's "no special-case handling needed" claim directly, not just
      trusting the comment)
- [x] This task's DoD does not assert any run `status` outcome — that
      belongs to T2.12a's boundary tests. Confirmed: same `AntiCheatResult`
      shape as T2.7/T2.8, no status field

---

### T2.10 — Anti-cheat check: elevation anomaly signal

**Objective:** Add the supporting signal that strengthens flagging
confidence without being a standalone trigger.

**Scope:**
- Yang dikerjakan: per tech-spec.md §2.4 — detect implausible elevation
  change in a short time window, add as a contributing flag (not a
  trigger on its own).
- Yang TIDAK dikerjakan: standalone rejection based on elevation alone —
  explicitly documented as a supporting signal only.

**Depends on:** T2.6, T2.6b

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.4 (Elevation anomaly row)

**Definition of Done:**
- [x] Synthetic route with an implausible elevation jump adds the correct
      flag alongside (not instead of) other checks —
      `backend/lib/anti-cheat/elevation-anomaly.ts`. Architecturally
      different from T2.7-T2.9 by necessity: this function takes the
      **other checks' excluded-segment set as an explicit input**
      (`checkElevationAnomaly(route, otherExcludedSegmentIndices)`) rather
      than deciding anything in isolation, since its entire behavior is
      conditional on another check having already fired on the same
      segment. Verified against T2.6b's real `elevation-anomaly.json`
      fixture (100m jump at segment 1): supplying `{1}` as the other
      check's exclusion produces `["elevation_anomaly_segment_1"]`;
      supplying `{0}` (a different segment) produces no flag, confirming
      the correlation is per-segment, not "any exclusion anywhere on the
      run". Threshold (`ELEVATION_ANOMALY_THRESHOLD_M = 50`,
      `ELEVATION_ANOMALY_WINDOW_SECONDS = 5`) is a starting value, not
      spec-given — same status as T2.9's threshold, tech-spec.md §2.4's
      row is qualitative here too
- [x] Elevation anomaly alone (without another trigger) does not flag a
      run — matches "additional signal, not a trigger tunggal" rule.
      Verified two ways: (1) `excludedSegmentIndices` is proven to be
      **always empty**, in every scenario tested, not just the isolated
      one — this function can never exclude a segment by itself, which is
      the stronger and more precisely correct claim than "doesn't flag
      alone"; (2) with an empty other-exclusions set, the real 100m/2s
      elevation jump produces zero `anomalyFlags` despite being a genuine
      anomaly by the threshold

---

### T2.11 — Trust score model + trust_multiplier

**Objective:** Turn repeated flagging into a graduated consequence instead
of a binary ban, per tech-spec.md's explicit false-positive concern.

**Scope:**
- Yang dikerjakan: implement `trust_multiplier(user)` exactly as specified
  in tech-spec.md §2.4's formula block (base 1.0; −0.10 per HIGH-confidence
  flag; −0.05 per LOW-confidence flag that did **not** end in auto-approve;
  +0.02 per clean run; floor 0.3; ceiling 1.0; rolling 30-day window,
  recomputed on each validated run), persist the result to
  `User.trust_score`, and apply it to `final_points` per §2.2's formula.
- Yang TIDAK dikerjakan: any manual admin review UI/tooling — operational
  tooling, not this phase. **Also not this task:** hiding low-trust users
  from the public leaderboard. That was previously in this task's scope,
  but the trust threshold for hiding is a separate number that
  tech-spec.md does not define, and verifying the exclusion requires
  T2.19's endpoint — which transitively depends on this task, so the DoD
  item could never be checked in sequence (found 2026-09-17). Leaderboard
  exclusion is now T2.19's own DoD item; the threshold itself is an open
  product decision tracked in [documents/README.md](../../README.md) §3.

**Depends on:** T2.7, T2.8, T2.9, T2.10

**Deliberately NOT depending on T2.12b**, despite the LOW-confidence decay
rule keying off whether a flag ended in auto-approve. A `T2.11 → T2.12b`
edge was added on 2026-09-17 and removed the same day: it creates a real
4-node cycle, `T2.11 → T2.12b → T2.12c → T2.12a → T2.11`, since T2.12a
already depends on T2.11. The dependency runs the other way round — T2.11
owns the *function*, and T2.12b (which already depends on T2.11
transitively) is responsible for **calling it again when a flag resolves**.
See T2.12b's own DoD for that trigger.

This also fixes a second problem the same edge was hiding: a LOW flag's
auto-approve exemption takes effect *at resolution time*, which is hours
or days after the run was validated. If trust were only ever recomputed on
a newly-validated run, an exempted flag would keep penalising the user
until their next run. Recomputation therefore has two triggers, not one.

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.4
(`trust_multiplier` formula block), §2.2 (where the multiplier is applied),
§2.4.1 (LOW/HIGH confidence and the auto-resolve window)

**Definition of Done:**
- [x] `trust_multiplier` returns exactly `1.0` for a user with no flags in
      the window — verified by unit test
      (`backend/lib/trust-score.test.ts`, `computeTrustMultiplier`)
- [x] Decay verified by unit test at each rate separately: one HIGH flag
      yields `0.90`; one LOW flag that was manually overridden (not
      auto-approved) yields `0.95`
      (`trust-score.test.ts`; also proved live below)
- [x] A LOW flag that auto-approved after `REVIEW_WINDOW_LOW` produces
      **no** decay — multiplier stays `1.0` — verified by unit test. This
      is the rule most likely to be implemented wrong, since it is the one
      case where a flag exists but must not count
      (`trust-score.test.ts` at the pure-formula level, `trust-score.db.test.ts`
      at the query level distinguishing `resolved_via='auto'` vs `'manual'`
      — this distinction needed a new nullable `run.resolved_via` column,
      added this task, since nothing in the existing schema recorded HOW a
      flagged run resolved. Also proved live below)
- [x] Floor verified: a user with 8 HIGH flags in the window computes to
      `0.20` before clamping and returns `0.3`, never lower, never `0`
      (`trust-score.test.ts`, plus a 50+50-flag extreme case)
- [x] Recovery verified: `+0.02` per clean run, where "clean" means
      `status = validated` **and** empty `anomaly_flags`; an `approved`
      run (previously flagged, later cleared) does **not** count as clean
      (`trust-score.test.ts` + `trust-score.db.test.ts`; also proved live below)
- [x] Ceiling verified: recovery never pushes the multiplier above `1.0`,
      including the case where clean runs outnumber flags
      (`trust-score.test.ts`)
- [x] Rolling window verified: a flag dated 31 days ago no longer affects
      the result, with no separate cleanup job involved — proved live below
      (window keyed on `run.created_at`, not `resolved_at`/`updated_at`,
      per tech-spec.md's own "umur flag" wording)
- [x] `final_points = raw_points × trust_multiplier` verified end-to-end
      through the real submission path, not just the function in isolation
      — proved live below
- [x] `User.trust_score` is persisted and recomputed on each validated run.
      The **second** recompute trigger — a flag resolving later — is
      T2.12b's DoD, not this task's, since this task must not depend on
      T2.12b (see the dependency note above)
      — proved live below

**Live verification (2026-09-17), deployed to
`https://backend-eight-gules-56.vercel.app`:** created a genuine Supabase
Auth test user via the Admin API, signed in for a real JWT, completed
their profile via the live `POST /api/profile/complete`. Seeded 6 real
`run` rows via `psql` with controlled `created_at`/`flag_confidence`/
`status`/`resolved_via` to build a known history within the 30-day window:
1 HIGH flag (10 days old), 1 LOW flag auto-approved (`resolved_via='auto'`,
15 days old), 1 LOW flag manually overridden (`resolved_via='manual'`, 5
days old), 2 clean `validated` runs (3 and 2 days old), plus 1 HIGH flag
**31 days old** (outside the window, to prove exclusion). Expected
pre-submission multiplier: `1.0 − 0.10(HIGH) − 0.05(LOW manual) +
0.02×2(clean) = 0.89` — the auto-approved LOW and the 31-day-old HIGH are
both correctly excluded. Submitted a real 10km/3600s run
(`avg_pace=360s/km` → pace bracket `1.0×` → `raw_points=10`) via the live
`POST /api/runs`: response was `final_points_awarded: 9` = `round(10 ×
0.89)`, confirming the multiplication. Queried `user.trust_score` via
`psql` afterward: `0.91` = `1.0 − 0.10 − 0.05 + 0.02×3` (the just-submitted
run now counts as a 3rd clean run), confirming recompute-on-submit. All
test data (7 run rows, the user row, the Supabase Auth identity) deleted
afterward and counts verified `0`.

---

### T2.12a — Wire anti-cheat pipeline + aggregate status resolution

**Objective:** Assemble T2.6–T2.11's outputs into the aggregate status
decision (`validated`/`flagged`/immediate-`rejected`) per tech-spec.md
§2.4.1's threshold model. This is the orchestration layer the anti-cheat
checks plug into — decoupled from ledger writes (T2.12c) and idempotency
(T2.12d) so each concern is independently completable, per the fix to
Round 2 finding C2-1 (the old monolithic T2.12 bundled six concerns and
bottlenecked four downstream tasks).

**Scope:**
- Yang dikerjakan: `POST /api/runs` request handler calls point calc
  (T2.6) + all four anti-cheat checks (T2.7–T2.10) + trust multiplier
  (T2.11) synchronously; aggregates `excluded_pct` as **count of
  excluded segments / total segments × 100** (tech-spec.md §2.4 — NOT
  distance-weighted) across all triggered checks; resolves aggregate
  status against
  `FLAG_THRESHOLD_PCT`/`REJECT_THRESHOLD_PCT`, and assigns
  `flag_confidence` (`low`/`high`, split at `FLAG_LOW_MAX_PCT`) when the
  outcome is `flagged` — all per tech-spec.md §2.4.1. This task and only
  this task owns the status/confidence decision.
- Yang TIDAK dikerjakan: `PointTransaction`/ledger writes, `User`
  aggregate updates (T2.12c); duplicate-submission idempotency (T2.12d);
  delayed flagged→approved/rejected resolution (T2.12b); load testing
  (T2.12e).

**Depends on:** T2.6, T2.7, T2.8, T2.9, T2.10, T2.11

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.4.1

**Definition of Done:**
- [x] Boundary tests at just-below-`FLAG_THRESHOLD_PCT`, within the LOW
      confidence sub-band, within the HIGH confidence sub-band, and
      at/above `REJECT_THRESHOLD_PCT` all resolve to the correct
      aggregate status and `flag_confidence`
      (`backend/lib/anti-cheat/status-resolution.test.ts`'s
      `resolveStatusFromExcludedPct` suite — exact percentages incl. both
      inclusive lower bounds; also proved live below with real GPS routes
      engineered to land on 0%/10%/30%/50% exactly)
- [x] Status/confidence resolution logic lives only here — T2.7–T2.10 do
      not decide status themselves (fix to Round 2 finding B-5)
      (unchanged from T2.7-T2.10: each still returns only
      `excludedSegmentIndices`/`anomalyFlags`; `resolveRunStatus` in
      `status-resolution.ts` is the only place that reads
      `FLAG_THRESHOLD_PCT` et al.)
- [x] `FLAG_THRESHOLD_PCT`/`REJECT_THRESHOLD_PCT`/`FLAG_LOW_MAX_PCT` read
      from configuration, not hardcoded
      (exported consts in `status-resolution.ts`, same pattern as
      `IMPLAUSIBLE_JUMP_SPEED_KMH`/`ELEVATION_ANOMALY_THRESHOLD_M`)

**Live verification (2026-09-17), deployed to
`https://backend-eight-gules-56.vercel.app`:** created a genuine Supabase
Auth test user, signed in for a real JWT, completed their profile.
Generated 4 real GPS routes (10 segments each) using T2.9's single-segment
teleport trigger (no streak requirement, so exact exclusion counts are
controllable) with 0, 1, 3, and 5 excluded segments — exactly 0%, 10%,
30%, and 50% — and submitted each via the live `POST /api/runs`:
`0% → {status: "validated", flag_confidence: null, resolved_at: <set>}`,
`10% → {status: "flagged", flag_confidence: "low", resolved_at: null}`,
`30% → {status: "flagged", flag_confidence: "high", resolved_at: null}`,
`50% → {status: "rejected", flag_confidence: null, resolved_at: <set>}` —
all four matching the inclusive-lower-bound boundary rule exactly. A
follow-up validated route with larger (50m) segments confirmed the
points-from-valid-segments wiring isn't silently broken:
`final_points_awarded: 1` (nonzero, as expected once clear of the
anti-farming floor). All 6 run rows, the user row, and the Supabase Auth
identity deleted afterward and counts verified `0`.

---

### T2.17 — GET /api/seasons/active endpoint + seed initial season

**Objective:** Give point transactions and (soon) leaderboard entries a
season to scope to — required before precompute can run meaningfully.

**Scope:**
- Yang dikerjakan: endpoint per database-api-spec.md §2.5, one seeded
  `Season` row with `status=active` for initial development/testing.
- Yang TIDAK dikerjakan: season lifecycle transitions (upcoming → active →
  ended) — that's Fase 3 (T3.6).

**Depends on:** T2.2

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §2.5

**Definition of Done:**
- [x] Endpoint returns the seeded active season matching the response
      shape in database-api-spec.md §2.5
      — verified live below
- [x] `PointTransaction` writes from T2.12c correctly reference this
      season's `season_id` — **closed 2026-09-18**, T2.12c now exists and
      its own live verification confirmed 3 real `point_transaction` rows
      all referencing this exact seeded season's `id`

**Live verification (2026-09-17), deployed to
`https://backend-eight-gules-56.vercel.app`:** seeded one `Season` row via
migration `20260917211241_seed_initial_season.sql`
(`WHERE NOT EXISTS` guard against double-seeding), confirmed live via
`psql` (`name="Season 1 — 2026"`, `status="active"`,
`start_at=2026-09-01`, `end_at=2026-11-30T23:59:59Z`). Created a genuine
Supabase Auth test user, signed in for a real JWT. `GET
/api/seasons/active` with no `Authorization` header → `401`. With the
real JWT → `200` and the exact seeded row plus a dynamically computed
`days_remaining: 75` (not hardcoded — recomputed from `end_at` vs
request time each call). Test Auth identity deleted afterward (no
`user`/`run` rows were created by this verification, so nothing else to
clean up).

---

### T2.12c — PointTransaction ledger write + User aggregate + season linkage

**Objective:** Persist T2.12a's status resolution as the authoritative,
append-only record, and return the full API response — the point at
which an active season must exist to link to.

**Scope:**
- Yang dikerjakan: writes `PointTransaction` (immutable) for `validated`/
  `flagged` outcomes (none for immediate `rejected`, per tech-spec
  §2.4.1); updates `User.total_points`/`current_level` from the ledger;
  references the active season's `season_id` (requires T2.17's seeded
  season to exist); returns the `201 Created` response shape from
  database-api-spec.md §2.2.
- Yang TIDAK dikerjakan: idempotency (T2.12d); delayed resolution of
  `flagged` runs (T2.12b).

**Depends on:** T2.12a, T2.17

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §2.2,
[tech-spec.md](../../02-architecture/tech-spec.md) §2.4.1

**Definition of Done:**
- [x] Response matches all three example shapes in database-api-spec.md
      §2.2 (validated, flagged, rejected), status code `201`
      (already built by T2.12a's `resolveRunStatus` wiring; re-verified
      live below)
- [x] No `PointTransaction` written for immediate `rejected` — verified
      by test, not just asserted in prose
      (`route.test.ts`'s rejected case asserts
      `recordRunPointsAndUpdateAggregateMock` is never called; also
      proved live below — 0 ledger rows for the rejected run)
- [x] Every written `PointTransaction` references a valid `season_id`
      from the season seeded by T2.17
      (`point-transaction.ts` looks up `season WHERE status='active'`
      and throws `NoActiveSeasonError` rather than writing a row without
      one; proved live below against the real seeded season)
- [x] `resolved_at` set correctly per status (null only while `flagged`)
      (unchanged from T2.12a, re-verified live below across all three
      statuses)
- [x] `User.total_points`/`current_level` correctly reflect the ledger
      after multiple runs
      (`total_points` is recomputed as `SUM(point_transaction.amount)`
      on every write, not incremented — same "recompute from source of
      truth" pattern as T2.11's `trust_score`; `current_level` via new
      `lib/levels.ts`, which T2.15 is expected to reuse rather than
      redefine. Proved live below across 3 ledger-writing runs)

**Live verification (2026-09-18), deployed to
`https://backend-eight-gules-56.vercel.app`:** created a genuine Supabase
Auth test user, signed in for a real JWT, completed their profile.
Submitted 4 real runs via the live `POST /api/runs`: two clean validated
runs, one LOW-flagged run (10% excluded via T2.9's teleport trigger), and
one rejected run (50% excluded) — each response matched its
database-api-spec.md §2.2 example shape exactly. Queried Postgres
directly afterward: exactly 3 `point_transaction` rows exist (validated ×
2, flagged × 1 — **zero** for the rejected run), all 3 referencing the
real seeded season's `id` (`0a23423a-...`, `status=active`); `run.resolved_at`
was set for both validated and the rejected row, and `null` for the
flagged row; `user.total_points` read back as `3` (1+1+1, matching the
ledger sum exactly) with `current_level=1`. All 3 `point_transaction`
rows, all 4 `run` rows, the `user` row, and the Supabase Auth identity
deleted afterward and counts verified `0`.

---

### T2.12d — Duplicate submission idempotency

**Objective:** Guarantee a retried submission (from the mobile sync
queue's retry logic, T2.14) never produces a second `PointTransaction`
for the same run — a concurrency/DB-constraint concern, deliberately
separated from anti-cheat orchestration.

**Scope:**
- Yang dikerjakan: unique constraint on `(user_id, started_at)` at the DB
  level; `POST /api/runs` returns the existing run's result on a
  duplicate submission instead of re-running the pipeline.
- Yang TIDAK dikerjakan: anti-cheat logic itself (T2.12a); ledger
  mechanics (T2.12c) beyond the uniqueness guard.

**Depends on:** T2.12c

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §3

**Definition of Done:**
- [x] Duplicate submission (same `user_id`+`started_at`) returns the
      existing result, no duplicate `PointTransaction`
      (`route.test.ts` — resolveRunStatus/insert/ledger all asserted
      never called on the duplicate path; proved live below)
- [x] Concurrent duplicate submissions (race condition, not just
      sequential retries) still produce exactly one `PointTransaction` —
      enforced by the DB constraint, not application-level locking alone
      (`route.test.ts` mocks a real Postgres `23505` error and asserts
      the app returns the winner's result, not a 500, and never
      double-writes the ledger; the constraint itself proved live below
      with two genuinely concurrent raw `psql` inserts — not just HTTP
      timing, which can't guarantee a true race)

**Live verification (2026-09-18), deployed to
`https://backend-eight-gules-56.vercel.app`:** migration
`20260918043221_add_run_unique_user_started_at.sql` adds
`run_user_id_started_at_key` (UNIQUE on `user_id, started_at`), confirmed
live via `psql \d run`. Created a genuine Supabase Auth test user, signed
in for a real JWT, completed their profile.
1. **Sequential retry:** submitted an identical run twice via the live
   `POST /api/runs` — first `201` (new), second `200` with the exact same
   `run_id`. Queried Postgres: exactly 1 `run` row and 1
   `point_transaction` row exist for that `started_at`.
2. **HTTP-level race:** fired two `POST /api/runs` requests with
   identical `user_id`+`started_at` truly concurrently (backgrounded
   shell jobs, not sequential). Both returned `200` with the same
   `run_id` — Postgres/network timing meant neither hit the insert path
   second, so this alone doesn't prove the DB-constraint code path, only
   the correct outcome (confirmed: exactly 1 `run` row for that
   `started_at`).
3. **Direct constraint proof:** to prove the constraint itself — not
   HTTP timing luck — is the actual backstop, ran two genuinely
   concurrent raw `psql` `INSERT`s for the same `(user_id, started_at)`
   as backgrounded shell jobs. One succeeded; the other failed with
   Postgres's own `duplicate key value violates unique constraint
   "run_user_id_started_at_key"` (error code `23505`, the exact error
   `route.ts` is written to catch) — confirmed only 1 row persisted.

All test `run`/`point_transaction` rows, the `user` row, and the Supabase
Auth identity deleted afterward and counts verified `0`.

---

### T2.12e — Load test / p95 latency verification

**Objective:** Verify the full pipeline (T2.12a + T2.12c + T2.12d) meets
tech-spec.md §4's response-time budget under realistic load — a
performance-engineering activity deliberately separated from correctness
work so it can't block correctness PRs, and vice versa.

**Scope:**
- Yang dikerjakan: basic load test against `POST /api/runs` at a defined
  synthetic volume, measuring p95 response time.
- Yang TIDAK dikerjakan: any functional changes — this task only measures
  and reports; a failing budget routes back to T2.12a/T2.12c for
  optimization.

**Depends on:** T2.12c, T2.12d

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §4

**Definition of Done:**
- [ ] p95 response time < 1.5s at a named synthetic load (e.g. 100
      concurrent submissions) — **ACCEPTED LIMITATION, pending re-test after
      the Supabase Pro upgrade (decision 2026-09-19). Not a blocker, and
      deliberately NOT being optimized now.** Actual measurements against the
      deployed backend: 2026-09-18, p95 **7,801 ms** (Vercel functions were in
      `iad1`, database in Singapore); 2026-09-19, after pinning functions to
      `sin1`, 100 concurrent submissions → 100 × `201`, all 100 rows persisted
      (no lost or duplicated writes), **p95 3,827 ms** (median 3,612 · p99
      3,908 · max 3,959). Sequential single-request p95 is 463 ms, so the code
      path itself is inside budget. The remaining time is queueing: throughput
      saturates near **25 submissions/s** (≈9 DB round-trips each) and median ≈
      p99, i.e. every request waits behind one shared limiter — most plausibly
      **Supabase Free-tier compute / PostgREST pool, not a code defect** (not
      proven; distinct-user concurrency was not tested). At the product's real
      pattern (~1 run per user per day) this ceiling is irrelevant. **Re-test
      trigger:** run `100 concurrent POST /api/runs` again once the project is
      on Supabase Pro (and, if it still misses, only then look at the ≈9-call
      write path). Related: T2.20a's rate limits bound how fast one client can
      push into this ceiling.
- [x] Result documented (load tool used, dataset size, measured p95)
      — the DoD only requires documenting the result, not passing it;
      see the live measurement below

**Re-measurement 2026-09-19 (Fase 2 audit), same target after pinning
Vercel to `sin1`:** 100 concurrent `POST /api/runs` from one test user →
**100 × 201, all 100 rows persisted** (no lost or duplicated writes), latency
median 3,612 ms · p90 3,794 · **p95 3,827** · p99 3,908 · max 3,959, wall
3,966 ms. Better than 7,801 ms, **still over the 1.5 s budget, so the first DoD
item stays unchecked.** Sequential single-request latency is fine (p95 463
ms, `scripts/verify-release.ts`), so the cost is queueing: throughput
saturates near 25 submissions/s (≈9 DB round-trips each) and every request
waits behind the same limiter — consistent with Supabase Free-tier compute /
PostgREST pool, not with the code path. Worst case by construction (one
user's ledger and trust recompute serialize); distinct users would likely do
better, which was not tested.

**Live measurement (2026-09-18), against
`https://backend-eight-gules-56.vercel.app`:** created a genuine
Supabase Auth test user, signed in for a real JWT, completed their
profile. **Tool:** a small Node.js script (`fetch` + `Promise.all`,
built-in to Node 22, no external load-test framework needed at this
scale) firing 100 concurrent `POST /api/runs` requests, each a distinct
~500m validated run (unique `started_at` per request so T2.12d's
duplicate-detection shortcut never triggers and the full pipeline
actually runs every time) from the same authenticated user.

**Result — 100 concurrent submissions:**
```
n=100, successCount=100, failedCount=0
p50=6655ms  p95=7801ms  p99=8235ms  max=8243ms  min=5434ms
```
Every request succeeded (`201`), but **p95 is ~5.2× the 1.5s budget.**

**Baseline (isolated, zero concurrency)** — a single `POST /api/runs`
with no other requests in flight, to separate "inherent per-request
latency" from "concurrency contention": **4757ms.** Already far over
budget alone. This rules out same-user row-contention as the primary
cause (the single-request baseline has none) and points instead at the
pipeline's own architecture: `POST /api/runs` currently makes roughly 9
sequential (not parallelized) Supabase round-trips per request —
duplicate-check (T2.12d), `trust_multiplier` query (T2.11), the `run`
insert (T2.12a), active-season lookup + `point_transaction` insert +
ledger `SUM` + `user` update (T2.12c, 4 calls), and a second
`trust_multiplier` query + update for the post-submission recompute
(T2.11). The concurrent run's p50 (6655ms) vs. the serial baseline
(4757ms) shows contention adds roughly 40% on top of that — real, but
secondary to the sequential-round-trip cost itself.

**Recommendation for the T2.12a/T2.12c optimization follow-up** (not
undertaken here — out of this task's scope): the two `trust_multiplier`
computations per request (once for points, once for the post-submission
recompute) are the most obvious duplicate-work target; several of the
remaining calls (e.g. the ledger `SUM` and the `user` update) could
plausibly be combined or parallelized with `Promise.all` where they
don't have a true data dependency on each other.

Test data (101 `run` rows, 101 `point_transaction` rows — 100 load-test
+ 1 baseline — the `user` row, and the Supabase Auth identity) all
deleted afterward and counts verified `0`.

---

### T2.12b — Anti-cheat resolution & auto-approve/reject lifecycle

**Objective:** Implement the confidence-based flagged→approved/rejected
state machine (tech-spec.md §2.4.1) so every `flagged` run has a defined
resolution path, and so the leaderboard precompute has a clear rule for
which runs count.

**Scope:**
- Yang dikerjakan: resolution logic for `flagged` runs, split by
  `flag_confidence`: **LOW** confidence auto-resolves to `approved`
  after `REVIEW_WINDOW_LOW` (default 48h) with no manual override —
  rationale for the 48h figure is in tech-spec.md §2.4.1 (long enough for
  a normal operator work cycle, short enough not to punish likely-
  legitimate users). **HIGH** confidence **never** auto-resolves — it
  stays `flagged` indefinitely until a human acts. Manual override
  runbook (direct DB action, no admin UI) documented for early
  `flagged→approved` or `flagged→rejected` on either confidence level;
  compensating negative `PointTransaction` written when a `flagged` run
  with an existing partial-points transaction is overridden to
  `rejected` (ledger stays append-only, tech-spec.md §4).
- Yang TIDAK dikerjakan: any admin review UI (explicitly out of v1
  scope, product-spec.md §5) — resolution is auto-threshold (LOW only) +
  runbook only; the immediate-`rejected`-at-submission path (already
  handled in T2.12a); actually registering this logic as a running
  scheduled job — that infra piece is T2.12f (Round 2 finding B-3: the
  logic alone has no owner without it).

**Depends on:** T2.12c

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.4.1

**Definition of Done:**
- [x] A LOW-confidence `flagged` run with no manual action resolves to
      `approved` after `REVIEW_WINDOW_LOW`
      (`resolve-flagged-runs.test.ts` + live below)
- [x] A HIGH-confidence `flagged` run with no manual action remains
      `flagged` indefinitely — explicitly tested, not just assumed
      (unit test asserts the overdue query itself filters on
      `flag_confidence='low'`; live below re-confirms a 100h-old HIGH row
      stayed completely untouched — same `updated_at` — across 3 separate
      resolve operations run against other rows)
- [x] A `flagged` run (either confidence) manually overridden to
      `rejected` produces a compensating negative `PointTransaction`,
      original transaction untouched, and `Run.final_points_awarded` is
      set to `0` (the net award — database-api-spec.md §1)
      (unit test + live below)
- [x] `resolved_at` **and** `updated_at` are set correctly on both auto-
      and manual resolution; `flag_confidence` is retained (not nulled)
      on both `approved` and override-`rejected` outcomes; `resolved_via`
      (`auto`|`manual`, added by T2.11 — database-api-spec.md §1) is also
      set on both paths — T2.11's `trust_multiplier` LOW-confidence
      exemption reads this column directly, so an unset `resolved_via`
      would silently make every LOW flag decay forever, auto-resolved or
      not (added 2026-09-17)
      (`updated_at` comes from T2.2's own DB trigger, unchanged; all
      other fields verified live below across all 3 resolved runs)
- [x] `REVIEW_WINDOW_LOW` and both threshold constants are configuration,
      not hardcoded
      (`REVIEW_WINDOW_LOW_HOURS` exported const, unit-tested = 48;
      T2.12a's `FLAG_THRESHOLD_PCT`/`REJECT_THRESHOLD_PCT` already
      exported consts from that task, unchanged here)
- [x] **Resolving a flag re-triggers `trust_multiplier` recomputation**
      (T2.11's function) for that user — verified for all three outcomes:
      a LOW flag auto-approving must *remove* its −0.05 decay, while a
      manual override to `rejected` must keep it. Without this the
      exemption would not take effect until the user's next validated run,
      which can be days later (added 2026-09-17)
      (all three outcomes proved live below with real `trust_score`
      values before/after each resolution)

**Manual-override runbook:** since an admin UI is explicitly out of v1
scope (product-spec.md §5), the "direct DB action" is a small CLI —
`backend/scripts/resolve-flagged-run.ts`, run via
`npx tsx --env-file=.env.local scripts/resolve-flagged-run.ts <run_id>
<approved|rejected>` — that calls `resolveFlaggedRun` directly rather
than asking an operator to hand-write the compensating-transaction SQL
themselves. Full procedure documented in
[anti-cheat-resolution-runbook.md](../../04-quality-security/anti-cheat-resolution-runbook.md).

**Live verification (2026-09-18), directly against the production
Supabase DB** (no new HTTP surface this task, so no Vercel deploy was
needed — `resolveFlaggedRun`/`autoResolveOverdueLowConfidenceFlags` were
invoked with `npx tsx --env-file=.env.local`, exactly as an operator
would use the runbook): created a genuine Supabase Auth test user,
completed their profile via the live `POST /api/profile/complete`.
Seeded 4 real `flagged` runs with matching `point_transaction` rows:
**A** (LOW, 50h old — overdue), **B** (HIGH, 100h old — must never
auto-resolve), **C** (LOW, 2h old — for manual-reject), **D** (HIGH, 1h
old — for manual-approve). Baseline `trust_score` (all 4 still flagged,
undecided): `0.70` = `1.0 − 0.10×2(HIGH) − 0.05×2(LOW)`.

1. Ran `autoResolveOverdueLowConfidenceFlags()` live: resolved exactly
   `[A]` — **B, C, D untouched** (B's `updated_at` unchanged from its
   original seed timestamp, proving zero writes touched it). A became
   `approved`/`resolved_via=auto`/`resolved_at` set,
   `flag_confidence='low'` retained. `trust_score → 0.75` (A's −0.05
   removed, exactly as expected).
2. Ran the runbook script on **C** → `rejected`: `final_points_awarded:
   8 → 0`; ledger shows the original `amount=8, type=run` row **and** a
   new `amount=-8, type=adjustment` row, same `season_id`, original
   untouched; `user.total_points: 24 → 16` (net effect of C is now 0).
   `trust_score` stayed `0.75` — C's −0.05 decay is unchanged because
   `resolved_via=manual`, not `auto` (correctly still decaying).
3. Ran the runbook script on **D** (HIGH) → `approved`: no new
   `PointTransaction` (count stayed `1`), `final_points_awarded`
   unchanged (`3`), `resolved_via=manual`. `trust_score` stayed `0.75`
   — HIGH decays unconditionally regardless of resolution outcome
   (tech-spec.md §2.4: "setiap flag HIGH selalu dihitung"), confirmed
   even after a manual approval.
4. **B re-checked after all of the above:** still `flagged`,
   `resolved_via`/`resolved_at` still null — proves DoD item 2 under
   real, non-trivial conditions, not just in isolation.

All test `run`/`point_transaction` rows, the `user` row, and the
Supabase Auth identity deleted afterward and counts verified `0`.

---

### T2.12f — Register resolve-flagged-runs as Vercel Cron job

**Objective:** Give T2.12b's LOW-confidence auto-resolve logic an actual
infrastructure trigger. Round 2 found this logic had no owning scheduled
job anywhere in the architecture (finding B-3) — this task closes that
gap.

**Scope:**
- Yang dikerjakan: Vercel Cron route
  (`app/api/cron/resolve-flagged-runs`) running on an interval ≤12h
  (bounds worst-case drift past the 48h `REVIEW_WINDOW_LOW` deadline to
  ≤12h), querying `flagged` runs where `flag_confidence = 'low' AND
  created_at < now() - REVIEW_WINDOW_LOW` and invoking T2.12b's
  resolution logic; schedule registered in `vercel.json`; node added to
  architecture.md §1's diagram (already done) and reflected in
  repo-coding-rules.md §1's `jobs/` description (already done).
- Yang TIDAK dikerjakan: the resolution logic itself (T2.12b) — this task
  only wires it to run automatically; HIGH-confidence flags are never
  queried by this job.

**Depends on:** T2.12b

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.4.1,
[architecture.md](../../02-architecture/architecture.md) §2 (step 8)

**Definition of Done:**
- [x] Job registered as a real Vercel Cron route with a schedule in
      `vercel.json` — not just application logic that nothing calls
      (confirmed via `vercel crons ls`, not just the file's presence —
      see live verification below)
- [x] A LOW-confidence `flagged` run left untouched auto-resolves to
      `approved` within `REVIEW_WINDOW_LOW` + one job interval (observed
      end-to-end, not just unit-tested)
      — proved live below via the actual deployed route
- [x] A HIGH-confidence `flagged` run is never touched by this job, no
      matter how long it remains unresolved
      — proved live below (200h-old HIGH run, untouched)

**Schedule note — interval is 24h, not ≤12h as originally scoped:** the
project is on Vercel's Hobby plan, which hard-rejects any cron
expression running more than once per day — confirmed live 2026-09-18 by
a real deploy attempt with `0 */6 * * *`:
`"Hobby accounts are limited to daily cron jobs... Upgrade to the Pro
plan to unlock all Cron Jobs features on Vercel."` This is a genuine
platform/billing constraint, not a code limitation — same category as
T2.3's Apple Developer Program blocker. Asked the user; they chose the
daily schedule (`0 0 * * *`) over upgrading to Pro. Worst-case drift past
the 48h `REVIEW_WINDOW_LOW` deadline is therefore up to 24h, not ≤12h —
tracked as an open item in [documents/README.md](../../README.md) §1,
not silently accepted as meeting the original target.

**Live verification (2026-09-18), deployed to
`https://backend-eight-gules-56.vercel.app`:** `vercel crons ls`
confirmed the job is genuinely registered (`/api/cron/resolve-flagged-runs`,
schedule `0 0 * * *`), not just declared in a file nothing reads. The
route requires `Authorization: Bearer $CRON_SECRET` (a real secret added
via `vercel env add`, Production, type Secret) — confirmed live:
no header → `401`; wrong secret → `401`; correct secret → `200`.
Created a genuine Supabase Auth test user, completed their profile.
Seeded 2 real `flagged` runs directly in Postgres: a LOW-confidence run
50h old (overdue) and a HIGH-confidence run 200h old. Invoked the live
deployed cron route (the same route Vercel's own scheduler calls, not a
local script) with the real secret: response
`{"resolvedCount":1,"resolvedRunIds":["<LOW run's id>"]}`. Queried
Postgres afterward: the LOW run was `approved`/`resolved_via=auto`; the
HIGH run was **completely untouched** — still `flagged`,
`resolved_via`/`resolved_at` still null. All test `run`/
`point_transaction` rows, the `user` row, and the Supabase Auth identity
deleted afterward and counts verified `0`.

---

### T2.13 — Anti-cheat verification pass (synthetic bad-data test suite) — gate task

**Objective:** This is the explicit checkpoint development-plan.md
requires before any leaderboard work begins — anti-cheat must be
*demonstrably* working, not just implemented.

**Scope:**
- Yang dikerjakan: automated test suite that reuses the T2.6b fixture
  corpus (does not author its own fixtures) to cover every case in
  tech-spec.md §2.4 (pace cap breach, GPS jump, teleport, elevation
  anomaly, combined cases, and clean/normal runs as negative controls),
  run against the real `POST /api/runs` pipeline (T2.12a→T2.12d); also
  verifies the confidence-based T2.12b/T2.12f resolution lifecycle: LOW
  confidence auto-resolves to `approved` after `REVIEW_WINDOW_LOW` via
  the actual registered Cron job, HIGH confidence never auto-resolves,
  and manual override (either confidence) produces a correct
  compensating transaction.
- Yang TIDAK dikerjakan: new anti-cheat rules beyond what's already
  specified — this task verifies, it does not design; building the
  fixture corpus itself (that's T2.6b).

**Depends on:** T2.12d, T2.12b, T2.12f

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §2.4, §2.4.1,
[development-plan.md](../development-plan.md) Fase 2 hard dependency

**Definition of Done:**
- [x] All four anti-cheat checks demonstrably trigger correctly against
      the T2.6b fixture corpus via automated tests
      (`app/api/runs/route.integration.test.ts` — real `POST /api/runs`
      HTTP handler, real Supabase, no mocks; each fixture asserted to
      surface its own check's flag prefix)
- [x] Negative controls (clean runs) produce zero false flags
      (both `clean-negative-control-*` fixtures asserted `validated`,
      `anomaly_flags: []`, through the same real pipeline)
- [x] Resolution lifecycle verified: LOW-confidence `flagged` →
      `approved` auto-resolve via the actual Cron job (T2.12f), HIGH-
      confidence `flagged` runs confirmed to NEVER auto-resolve, and
      manual `flagged` → `rejected` override produces a correct
      compensating transaction
      (`lib/anti-cheat/resolve-flagged-runs.integration.test.ts`, real DB,
      seeded flagged rows exercised through `autoResolveOverdueLowConfidenceFlags`/
      `resolveFlaggedRun` — the same functions T2.12f's Cron route and the
      manual-override runbook call)
- [x] Test suite is part of the CI pipeline (not a one-off manual run)
      — proved live below with a real GitHub Actions run, not just the
      workflow file's presence
- [x] Sign-off recorded: this task is the explicit gate T2.21 checks for
      before enabling the public leaderboard
      — **signed off 2026-09-18**, see below

**How "real pipeline, not mocks" was achieved in CI, not just locally:**
Two new integration test files
(`app/api/runs/route.integration.test.ts`,
`lib/anti-cheat/resolve-flagged-runs.integration.test.ts`) hit the real
hosted Supabase project directly — genuine Auth users created/torn down
per run, real Postgres rows, zero mocking of `resolveRunStatus`,
`trust_multiplier`, the ledger, or the resolution lifecycle. They
`describe.skipIf` gracefully when `NEXT_PUBLIC_SUPABASE_URL`/
`SUPABASE_SERVICE_ROLE_KEY`/`NEXT_PUBLIC_SUPABASE_ANON_KEY` aren't present
(e.g. a contributor's fresh clone), so `npm test` never hard-fails for
lacking them — but genuinely run when they are, which required:
1. Adding those 3 as **GitHub Actions repository secrets** on
   `riporipo223/laju-app` (the CLI's PAT lacked the scope to set these
   itself — HTTP 403 on `gh secret set`; the user added them manually via
   the GitHub web UI).
2. Passing them through in `.github/workflows/ci-backend.yml`'s `npm test`
   step as `env:`.
3. **Fixing a genuine pre-existing CI bug that predates this session**
   (first appeared on the very first scaffold commit, 2026-09-14, confirmed
   via `gh run list`'s history): `eslint.config.mjs` used
   `FlatCompat.extends("next/core-web-vitals", "next/typescript")`, but
   `eslint-config-next@16.3.5` already ships native flat config — routing
   it through `FlatCompat`'s legacy-eslintrc translation path crashed with
   `TypeError: Converting circular structure to JSON` (reproduced locally,
   identical trace). Without this fix, `npm run lint` crashed before
   `npm test` could even run, blocking DoD item 4 entirely. Fixed by
   importing `eslint-config-next/core-web-vitals` and
   `eslint-config-next/typescript` directly (same rules, same plugins,
   nothing weakened — just the correct loading mechanism for this package
   version). The repo's config-protection hook initially blocked this edit
   (by design, to stop silent rule-weakening); the user reviewed the fix
   and disabled it for this one change.

**Live CI verification (2026-09-18):** pushed to `main`
(`riporipo223/laju-app`), GitHub Actions run
[35324735602](https://github.com/riporipo223/laju-app/actions/runs/35324735602)
— `conclusion: success`. Log confirms the integration suites **ran for
real, not skipped**: `✓ lib/anti-cheat/resolve-flagged-runs.integration.test.ts
(3 tests) 10694ms`, `✓ app/api/runs/route.integration.test.ts (6 tests)
17346ms`, overall `Test Files 19 passed (19)`, `Tests 122 passed (122)`.
Verified afterward (via `psql` and the Supabase Admin API) that CI's own
test runs left zero stray `user`/`run` rows or Auth identities — the
`afterAll` cleanup in both integration files ran correctly even from a
GitHub-hosted runner.

**Sign-off:** T2.13's gate is satisfied. All four anti-cheat checks and
the confidence-based resolution lifecycle are demonstrably working
against the real `POST /api/runs` pipeline, verified by an automated
suite that genuinely executes in CI (not a one-off manual run), with
zero data leakage. T2.21 may treat this gate as passed.

*(No `deferred-manual-tests.md` sweep item here, deliberately. T2.13 is a
narrow anti-cheat verification gate; T2.21 is the phase-wide release gate
and carries that sweep. Putting it on both would let an unrelated row —
e.g. T2.0a's tab-bar rendering check — block anti-cheat sign-off, which is
not what the rule is for. Added then removed 2026-09-17.)*

---

### T2.14 — Mobile sync queue (offline → online push, retry, initial status apply)

**Objective:** Connect Fase 1's offline-first local storage to the now-
working backend. Covers only the *initial* status from the submission
response — later resolutions of a `flagged` run are T2.14d (via the
T2.14c endpoint), not this task (title deliberately no longer says
"status reconciliation").

**Scope:**
- Yang dikerjakan: background sync service (Swift, Data/Sync layer) pushing
  runs with local `syncStatus = pendingSync` to `POST /api/runs` (via
  `URLSession`) when connectivity is available, retry on failure, update
  local `syncStatus` to `synced` and write `serverRunId`, `serverStatus`,
  `flagConfidence`, `finalPointsAwarded`, `anomalyFlags`, `resolvedAt` from
  the server's `201` response (tech-spec.md §3, attributes per T0.6) — note
  `syncStatus` (client-only) is distinct from `serverStatus`/server
  `RUN.status` (tech-spec.md §2.4.1).
- Yang TIDAK dikerjakan: any UI beyond a basic sync status indicator
  (product-spec.md §3 Should-have — minimal is fine here); reconciling a
  `flagged` run's *later* resolution — that is entirely T2.14d's scope
  (the endpoint itself is T2.14c).

**Depends on:** T2.12d, T0.6

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §3

**Definition of Done:**
- [x] A run recorded fully offline syncs automatically once connectivity
      returns
      (`SyncServiceTests.testSyncsAutomaticallyWhenConnectivityReturns` —
      real `SyncService`, fake `PathMonitoring` triggers the same
      connectivity-handler code path the real `NWPathMonitorAdapter`
      would; app also confirmed to boot cleanly with the *real* adapter
      wired in, live in the Simulator. Full real-device airplane-mode
      transition tracked in
      [deferred-manual-tests.md](../../04-quality-security/deferred-manual-tests.md),
      same category as this file's other real-environment tests)
- [x] Local `estimatedPoints` is replaced by server `final_points_awarded`
      (stored locally as `finalPointsAwarded`) in the UI after sync
      (`testFinalPointsAwardedPopulatedFromServerResponse` — scope is the
      data write itself, per this task's own "Yang TIDAK dikerjakan: any
      UI beyond a basic sync status indicator")
- [x] Repeated sync failures do not drop the run — it remains queued and
      retried, never silently discarded
      (`testFailedSyncLeavesRunQueuedForRetry` — a `500` leaves
      `syncStatus` untouched, a follow-up call then succeeds, proving the
      run genuinely stayed queryable; `testNetworkErrorAlsoLeavesRunQueuedForRetry`
      covers the network-layer failure case separately)
- [x] After a successful sync, the local row's `serverRunId`,
      `serverStatus`, `flagConfidence`, `anomalyFlags`, and `resolvedAt`
      (T0.6 attributes) are populated from the `201` response — verified
      specifically for a **`flagged`** response, since
      `serverStatus = "flagged"` is the entire trigger condition T2.14d
      watches for and `serverRunId` is the only correlation key it has
      (`testFlaggedResponsePopulatesAllServerFields` — all 5 fields
      asserted individually against a real `flagged`-shaped response body,
      including `resolvedAt == nil`, the case most likely to be gotten
      wrong)
- [x] **Permanent rejections leave the upload queue** (Fase 2 audit,
      2026-09-20, commit b32c409): `400/413/422` → local
      `syncStatus = "rejectedPermanent"`, never resent, row kept in local
      history; transient (`401/403/404/409/429/5xx`, network) stay
      `pendingSync`. `SyncPermanentRejectionTests` (6 tests, incl. exactly 1
      request over 3 cycles, batch not blocked, nothing deleted); full iOS
      suite 147/147, CI (iOS) green. Root cause of the 69/127 device runs
      with distance ≤ 0: start/stop taps without movement (median 4 s, median
      1 GPS point, none with ≥ 5 points and ≥ 60 s, all distance exactly 0,
      35 on 13 Sep during on-device testing) — testing artifacts, no evidence
      of a movement/distance bug.

**Implementation:** `ios/Laju/Services/Networking/` (new — `APIConfig`,
`APIClient`, `RunSubmissionDTOs`) and `ios/Laju/Services/Sync/` (new —
`SyncService`, `PathMonitoring`/`NWPathMonitorAdapter`), wired into
`LajuApp.swift` alongside `authService`. A real bug was caught and fixed
before any of this shipped: the server's `resolved_at` includes
fractional seconds (confirmed against real backend responses all through
Fase 2's live verifications, e.g. `"2026-09-18T04:26:30.381Z"`) —
Foundation's built-in `.iso8601` `JSONDecoder` strategy cannot parse that
form, so `RunSubmissionCoding.makeDecoder()` tries fractional-seconds
first, falling back to the plain form, rather than silently failing to
decode a response shape that's actually common.

**Verification:** `SyncServiceTests.swift` (8 new tests, all passing) —
real `SyncService`/`APIClient` classes, `URLProtocol`-stubbed network
(no real backend call in the automated suite) and a fake
`PathMonitoring` (no real connectivity toggling). Full iOS suite run
afterward: **97/97 tests passing** (89 previous + 8 new), zero
regressions. `xcodebuild ... build` succeeds cleanly (Swift 6 strict
concurrency, warnings-as-errors). App launched in the iPhone 17 Pro
Simulator with the *real* `NWPathMonitorAdapter` wired in at the app
root — confirmed no crash on cold launch, proving the production
connectivity-monitoring code path (not just its test double) is sound.

**CI (iOS) was genuinely green for the first time in this repo's history
as a result of this task (2026-09-18)** — every prior run of
`.github/workflows/ci-ios.yml` had failed since it was first added
(2026-09-12), for reasons entirely unrelated to T2.14's own code. Fixed
along the way, same "unblock CI, don't just work around it locally"
principle as T2.13's eslint fix:
1. **Real SwiftLint violations in the new code** (`SyncServiceTests.swift`
   — force-unwraps, an implicitly-unwrapped-optional instance property,
   a non-optional `String`→`Data` conversion, `override class func` where
   `override static func` is preferred in a `final class`) — never caught
   locally because `swiftlint`/`swiftformat` were never run as part of
   this task's own edit-then-`xcodebuild` loop. Fixed by refactoring
   `context` to a per-test local (matching every other test file's
   existing convention) and correcting the rest directly.
2. **A genuine `swiftformat`/`swiftlint` rule conflict**, exposed (not
   caused) by a routine `swiftformat .` run touching
   `OnboardingSignInStep.swift` (pre-existing, T2.3): SwiftFormat's
   `wrapMultilineStatementBraces` wants a multiline `if` condition's
   opening brace on its own line; SwiftLint's `opening_brace` wants it on
   the same line as the last condition. Fixed by disabling
   `wrapMultilineStatementBraces` in `.swiftformat` (the rest of the
   codebase already consistently uses the same-line style SwiftLint
   expects) and restoring that one brace by hand.
3. **A CI-only Swift 6 concurrency build error** in `RunHistoryView.swift`
   (pre-existing, unrelated to sync) — `MKMapSnapshotter.Snapshot` isn't
   `Sendable` on the older Xcode bundled with the `macos-15` GitHub
   Actions runner image, unlike this machine's local Xcode 26.3, where
   the same code compiles clean. Fixed with `@preconcurrency import
   MapKit` — the exact remedy the compiler's own error suggested, safe on
   both SDK versions.

Each fix was verified locally (`swiftlint --strict`, `swiftformat --lint
.`, full `xcodebuild test`, 97/97 passing every time) before pushing, and
the **final push's actual GitHub Actions run
([35331631809](https://github.com/riporipo223/laju-app/actions/runs/35331631809))
is `conclusion: success`**, with its own log confirming "Executed 97
tests, with 0 failures" — not just a green checkmark. Backend CI has the
same status as of T2.13 — both pipelines are now real, working gates for
the first time in the project's history.

---

### T2.14c — GET /api/runs status reconciliation endpoint

**Objective:** Give the client a way to learn about a `flagged` run's
resolution that happens *after* the run is already synced — LOW
confidence auto-resolves up to `REVIEW_WINDOW_LOW` (48h) later, HIGH
confidence resolves at an arbitrary later time via manual override
(tech-spec.md §2.4.1, §3 step 7). Backend contract only — the client
loop that calls it is T2.14d, split out per the same
orchestration/consumer pattern already used for T2.12a↔T2.12c and
T2.15↔T2.16. This endpoint, and its supporting schema (T2.2's
`updated_at`, T0.6's local mirror columns), were redesigned as one unit
after 4 rounds of incremental patching each surfaced the next missing
layer (endpoint → filter column → local columns → gate wiring) — see
development-plan.md Fase 2 for the consolidated design note.

**Scope:**
- Yang dikerjakan: `GET /api/runs?since=<ISO8601, optional>`
  (database-api-spec.md §2.2b) filtering on `Run.updated_at >= since`
  (not `resolved_at`, which is null for any still-`flagged` run and
  would silently miss the transition *into* `flagged` too); `since`
  omitted → default `now() - 90 days` lookback (the only legal way to
  seed a client's first-ever call, since no server timestamp exists on
  the client before this); `since` present but unparseable → `400`;
  response includes `server_time` (clock-skew-safe cursor source) and
  `has_more` (true when the 200-row cap truncates the result, ordered
  `updated_at` **ASC** so draining forward via the last-row cursor never
  skips rows the way a DESC + `server_time`-cursor approach did in an
  earlier draft — that ordering skipped everything still undrained);
  each row carries `run_id`, `status`, `flag_confidence`,
  `final_points_awarded`, `anomaly_flags`, `resolved_at`, `updated_at`;
  scoped to the authenticated caller's own runs only.
- Yang TIDAK dikerjakan: the client-side call scheduling, cursor
  persistence, local-row updates, or cache invalidation — all of that is
  T2.14d; general run-history pagination — this endpoint is scoped to
  status reconciliation only; the local schema itself (T0.6 already
  creates it).

**Depends on:** T2.2, T2.12b

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §2.2b, §3,
[tech-spec.md](../../02-architecture/tech-spec.md) §4 (reconciliation NFR row)

**Definition of Done:**
- [x] Deployed; `400` only for a present-but-unparseable `since`, never
      for a missing one (server defaults the lookback instead) —
      deployed to `https://backend-eight-gules-56.vercel.app`; live
      curl: `GET /api/runs` (no JWT) → `401`, `GET /api/runs` (valid JWT,
      no `since`) → `200`, `GET /api/runs?since=not-a-date` (valid JWT)
      → `400`
- [x] Response includes `server_time` and `has_more`, capped at 200 rows
      ordered `updated_at` ASC (`route.test.ts` — asserts `order` called
      with `("updated_at", {ascending:true})` and `limit(201)`)
- [x] With >200 qualifying rows: response contains the 200
      oldest-changed rows and `has_more: true`; a follow-up call using
      the last row's `updated_at` as `since` returns the next batch, and
      repeating eventually reaches `has_more: false` with no row ever
      skipped — verified by test, not just asserted in prose
      (`route.integration.test.ts` — real DB, seeded 201 rows for one
      real Supabase Auth user, drained in 2 calls, union of both pages
      covers all 201 run ids exactly once; re-verified live against the
      deployed endpoint with a genuine second submission covering the
      boundary row)
- [x] A run whose `updated_at` changed but whose `resolved_at` is still
      `null` (i.e. a run that just transitioned *into* `flagged`) **is**
      returned by `?since=` — verified by test, so a
      `resolved_at`-based filter implementation cannot pass this item
      (`route.test.ts` — flagged run with `resolved_at: null` present in
      mocked response and asserted returned; the real query itself
      filters on `updated_at`, never `resolved_at`, confirmed by reading
      `route.ts`)
- [x] Response matches both example shapes in database-api-spec.md
      §2.2b, including the `flagged → rejected` override entry with
      `flag_confidence` retained (not null) and `final_points_awarded: 0`
      (`route.test.ts` — asserts `flag_confidence: "high"`,
      `final_points_awarded: 0` on the override-shaped row)
- [x] Requests return only the authenticated caller's own runs — verified
      with a second user's token (no cross-user leakage)
      (`route.integration.test.ts` — two genuine Supabase Auth users,
      each with their own run; second user's token never returns the
      first user's runs and vice versa; re-verified live against the
      deployed endpoint with two fresh real Auth identities)
- [x] `Run.updated_at` index in place; p95 < 300ms per tech-spec.md §4 —
      composite index `run_user_id_updated_at_idx (user_id, updated_at)`
      confirmed live via `\d run` (from T2.2); `EXPLAIN ANALYZE` of the
      exact production query against 5000 seeded rows for one user shows
      an **Index Scan** (not sequential), `Execution Time: 0.135ms` —
      well under the 300ms target. Note: a raw client-observed round
      trip from the test machine to the deployed endpoint measured
      1.1s–3.1s across repeated warm calls; that gap is geographic
      network RTT + Vercel serverless invocation overhead, not query
      cost — the NFR (tech-spec.md §4) targets query response time,
      which the `EXPLAIN ANALYZE` figure demonstrates directly. Not
      massaging this: if full end-to-end client latency matters for the
      mobile client's UX, that's a distinct infra concern already
      tracked under **PERF-1**/**OPS-1** in documents/README.md, not
      something this endpoint's query design can fix

---

### T2.15 — GET /api/users/me/progress endpoint

**Objective:** Expose the server-authoritative version of Fase 1's local
progress screen.

**Scope:**
- Yang dikerjakan: endpoint per database-api-spec.md §2.3
  (total_points, current_level, points_to_next_level, trust_score).
  `current_level`/`points_to_next_level` derived from a `levelThresholds`
  config copy in `backend/lib` that must match database-api-spec.md §1's
  table exactly, row for row — same requirement as T1.3's Swift copy.
- Yang TIDAK dikerjakan: mobile UI changes (T2.16).

**Depends on:** T2.12c

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §2.3, §1
(Level note)

**Definition of Done:**
- [x] Response shape matches database-api-spec.md §2.3 example —
      deployed to `https://backend-eight-gules-56.vercel.app`; live curl
      returns exactly `{total_points, current_level, points_to_next_level,
      trust_score}`, no extra/missing fields, matching the spec's own
      example values field-for-field when fed the same inputs (total
      1240 → `points_to_next_level: 260`, matching the doc's literal
      example — note the doc's paired `current_level: 6` in that same
      example is not internally consistent with the levelThresholds table
      for 1240 points (real answer is level 4); the endpoint always
      trusts the stored `current_level` column, which T2.12c's
      `recomputeUserPointsAggregate` keeps correctly derived, so this is
      a pre-existing doc-example inconsistency, not an endpoint bug)
- [x] Values match what's derivable from the `PointTransaction` ledger for
      that user (`route.integration.test.ts` — real DB: two real ledger
      rows written via the real `recordRunPointsAndUpdateAggregate`,
      independently re-summed straight from `point_transaction`, and the
      endpoint's `total_points` asserted equal to that independent sum,
      not just to what `recordRunPointsAndUpdateAggregate` itself
      returned; re-verified live against the deployed endpoint)
- [x] Backend `levelThresholds` values match database-api-spec.md §1's
      table exactly, row for row — verified by a test (same as T1.3's
      requirement on the Swift side) (`lib/levels.test.ts`, pre-existing
      from T2.12c, all 8 rows asserted `toEqual` the spec table verbatim)

---

### T2.16 — Update mobile profile/progress screen to use server data

**Objective:** Replace Fase 1's local-only progress screen with the
server-backed, authoritative version.

**Scope:**
- Yang dikerjakan: T1.6's ViewModel (`ProgressViewModel`) now fetches from
  `GET /api/users/me/progress` via `URLSession`, exposed through
  `@Published` state, falls back to local estimate when offline/unsynced.
  Exposes an explicit, externally-callable `refresh()` method that
  re-issues the `GET /api/users/me/progress` call — this is the hook
  T2.14d's reconciliation loop calls after a background status update, and
  is a **separate mechanism from Core Data change notifications**: saving
  a `Run` object triggers a local re-render of that run's row (e.g. in run
  history), but does **not** by itself re-fetch server-derived
  points/level — only `refresh()` does that. A resolved-run reaching the
  device requires both: T2.14d writes the `Run` object AND calls
  `ProgressViewModel.refresh()`.
- Yang TIDAK dikerjakan: any new progress metrics beyond what the endpoint
  returns.

**Depends on:** T2.15, T2.14

**Reference:** [architecture.md](../../02-architecture/architecture.md) §3 (State layer)

**Definition of Done:**
**Note (spec vs reality):** the Scope above says "T1.6's ViewModel
(`ProgressViewModel`)", but T1.6 never built a ViewModel — it was
implemented inline in `ProfileView` via `@FetchRequest`. `ProgressViewModel`
was therefore created new here (`ios/Laju/ViewModels/ProgressViewModel.swift`),
owned at the app root (`LajuApp`, same precedent as `SyncService`) and
injected via `.environmentObject`, so `refresh()` stays callable from
outside the screen.

- [x] Screen shows server-derived values when online/synced —
      `ProfileView.levelSection` renders `progressViewModel.serverProgress`
      when non-nil (`ProgressViewModelTests.testRefreshPopulatesServerProgressFromResponse`
      — real `ProgressViewModel` + real `APIClient`, stubbed `URLSession`).
      **Not verified visually:** the server branch needs a signed-in
      Supabase session, which needs Sign in with Apple (blocked on Apple
      Developer Program, same as T2.3/T2.4). The backend side of this
      contract is live-verified (T2.15)
- [x] Screen gracefully falls back to local estimate when offline (no
      broken UI state) — `serverProgress` stays `nil` on network failure
      or missing session, never fabricated
      (`testRefreshLeavesServerProgressNilOnNetworkFailure`,
      `...NilWhenNotSignedIn`), and a later failure preserves an earlier
      good value (`testRefreshPreservesLastKnownGoodValueOnASubsequentFailure`).
      Confirmed visually in the iPhone 17 Pro Simulator (not signed in):
      Profile renders "Level 1 — Pemula / 0 total points / 100 points to
      next level" from the local path, no blank/broken state
- [x] `ProgressViewModel.refresh()` is callable from outside the screen
      (e.g. T2.14d) and re-fetches `GET /api/users/me/progress` — verified
      directly, not only via the screen's own initial load
      (`testRefreshIsCallableDirectlyAndReFetchesEachCall` — two direct
      calls, no view involved, second call returns the new server value,
      request count = 2)

Full iOS suite 104/104 (97 + 5 `ProgressViewModelTests` + 2
`LevelProgressionTests.title(forLevel:)`), `swiftlint --strict` and
`swiftformat --lint` clean.

---

### T2.14d — Client status reconciliation loop

**Objective:** Drive T2.14c's endpoint from the mobile client — cadence,
cursor persistence, local-row updates, and cache invalidation. Split
from the endpoint itself because the two have almost disjoint dependency
sets (this task needs T0.6/T2.14/T2.16, the endpoint needs only
T2.2/T2.12b) and bundling them was making the combined task's DoD list
longer than any other task in this phase.

**Scope:**
- Yang dikerjakan: calls T2.14c **only when** the client holds at least
  one locally-stored run with `serverStatus = flagged` (T0.6), and only
  if ≥15 minutes have elapsed since the last reconciliation *attempt*
  (`SyncMeta.lastReconcileAttemptAt`, updated on every attempt — success
  or failure — so the cadence survives app restarts); called on app open
  (subject to the same cadence floor) and on sync cycles. On the very
  first call, omits `since` entirely (per T2.14c's default). After
  **every** response, persists the next `since` into
  `SyncMeta.lastReconciledAt` — **`server_time`** when `has_more: false`
  (window fully drained), or **the last returned row's `updated_at`**
  when `has_more: true` (window not yet drained; persisting `server_time`
  here would skip everything still undrained if the app is killed
  mid-drain) — never a device timestamp either way. When `has_more:
  true`, re-calls immediately after persisting that cursor, repeating
  until `has_more: false`. **Termination guard** (database-api-spec.md
  §2.2b): because the filter is inclusive (`>= since`), a batch of ≥200
  runs sharing one identical `updated_at` re-returns that same boundary
  row on the follow-up call — this is expected and harmless (idempotent
  overwrite), but the loop must break once a follow-up call returns **no
  row newer than the current cursor**, instead of re-calling forever.
  For each returned run, matches it to a local `Run` object by
  `serverRunId` (a returned `run_id` with no matching local row is
  ignored, not inserted); updates the local `serverStatus`,
  `flagConfidence`, `finalPointsAwarded`, `anomalyFlags`, `resolvedAt`
  (T0.6 attributes), saves the Core Data context, and calls
  `ProgressViewModel.refresh()` (T2.16) so a resulting points/level change
  re-renders — including a level *decrease*, which is expected (tech-spec
  §2.4.1), not an error state. **This is a separate step from the Core
  Data save** — saving the `Run` object alone re-renders that run's own
  row (e.g. in run history via `@FetchRequest`) but does not re-fetch
  server-derived profile/progress data; only the explicit `refresh()` call
  does that (see T2.16). On failure, updates the attempt timestamp but not
  `lastReconciledAt`, and never touches T2.14's separate upload-retry
  queue.
- Yang TIDAK dikerjakan: the endpoint contract itself (T2.14c); rendering
  the resulting status as user-facing copy (T2.14b); any backoff beyond
  the flat 15-minute floor for an indefinitely-`flagged` HIGH-confidence
  run — continuing to poll it forever is deliberate (tech-spec §3 step 7),
  not a bug to be "fixed" with unspecified backoff later.

**Depends on:** T2.14c, T2.14, T0.6, T2.16, T2.12f

**Reference:** [tech-spec.md](../../02-architecture/tech-spec.md) §3 step 7,
[architecture.md](../../02-architecture/architecture.md) §2 step 10,
[database-api-spec.md](../../02-architecture/database-api-spec.md) §2.2b

**Definition of Done:**

**Live findings while building (real `GET /api/runs` against the deployed
backend, not stubs):** (1) `updated_at`/`resolved_at` come back from
PostgREST with **microseconds** (`2026-09-18T19:45:59.395546+00:00`), which
`ISO8601DateFormatter` rejects — the shared decoder
(`RunSubmissionCoding.makeDecoder`) gained a fractional-truncation
fallback; without it every real response would have failed to decode.
(2) `final_points_awarded` is **nullable** in the DB (a freshly-flagged row
returned `null`) — `ReconciledRun.finalPointsAwarded` is therefore
optional, and a null never overwrites a known local value; a non-optional
field would have failed the whole page and, since the cursor never
advances on failure, retried the same failing page forever.

- [x] Client skips the call entirely when it holds zero locally-`flagged`
      runs (`testSkipsCallEntirelyWhenNoFlaggedRun` — no request, no
      attempt timestamp written)
- [x] Calls respect the ≥15-minute-since-last-attempt floor, including
      across an app restart (`testFifteenMinuteFloorSurvivesRestart` — a
      brand-new `ReconciliationService` over the same store: 14 min →
      skipped, 16 min → called; only the persisted `SyncMeta` carries state)
- [x] First-ever call omits `since`; every subsequent call sends the
      server-issued cursor, never a device timestamp
      (`testFirstCallOmitsSinceAndNextCallUsesServerTimeDespiteSkewedClock`
      — device clock advanced a decade between calls; second call's `since`
      is exactly the prior response's `server_time`)
- [x] A `has_more: true` response is fully drained via immediate
      follow-up calls (`testHasMoreIsDrainedWithLastRowCursorThenServerTime`
      — 2 calls in one cycle, follow-up `since` = last row's `updated_at`,
      final persisted cursor = last response's `server_time`)
- [x] A batch of ≥200 rows sharing one identical `updated_at` terminates
      the drain loop (`testIdenticalUpdatedAtBatchTerminatesTheDrainLoop`
      — 200 identical rows with `has_more: true` forever; exactly 2 calls,
      then stops)
- [x] flagged → approved/rejected is reflected in the local row **and**
      triggers `ProgressViewModel.refresh()`
      (`testResolutionUpdatesLocalRowAndTriggersProgressRefresh` — all 5
      T0.6 attributes updated, refresh hook fired exactly once; an
      unchanged row does not fire it). Wired in `LajuApp` as
      `onRunsChanged: { await progress.refresh() }`
- [x] An unmatched `run_id` is ignored, not inserted
      (`testUnmatchedRunIdIsIgnoredNotInserted` — `Run` count stays 1)
- [x] A failed call updates the attempt timestamp but not
      `lastReconciledAt`, and does not affect T2.14's upload-retry queue
      (`testFailureStoresAttemptButNotCursorAndLeavesUploadQueueAlone` —
      a `pendingSync` run stays `pendingSync`). Signed-out is deliberately
      *not* an attempt (`testSignedOutIsNotAnAttempt`)

Triggers: called from `SyncService.onCycleFinished` (fires after every
`syncPendingRuns()`, which itself runs on app-active and on
connectivity-restored) — covers "app open and sync cycles" with one hook.
**Not verified end-to-end on a device/Simulator with a real session:** that
needs a signed-in Supabase session (Sign in with Apple, blocked on the
Apple Developer Program). The server contract half is live-verified above
and in T2.14c. iOS suite 116/116 (104 + 12 `ReconciliationServiceTests`),
`swiftlint --strict` and `swiftformat --lint` clean.

---

### T2.14b — Surface anomaly reason & resolution status to user

**Objective:** Close product-spec AC 4.3.2 ("user diberi tahu alasannya
mis. run diflag") — a Must-have acceptance criterion with zero task
coverage through 3 audit rounds, despite `anomaly_flags` being written
server-side since T2.7 was first speced. Purely a client-side
presentation task — the response contract itself (including
`flag_confidence`) is T2.12c's DoD, not this task's; T2.14d owns
fetching updates. This task only turns already-available local data into
copy the user sees.

**Scope:**
- Yang dikerjakan (client only): a flag-code → human-readable message
  lookup table (e.g. `gps_speed_jump_segment_3` → "Lari kamu kedeteksi
  lompat lokasi tiba-tiba"); run summary/history entry (SwiftUI) shows
  status-appropriate copy read from the local `serverStatus`/
  `flagConfidence`/`anomalyFlags` attributes (T0.6): `flagged`+`low` →
  "poin tertahan sementara, otomatis diproses dalam ≤48 jam";
  `flagged`+`high` → "poin ditahan, perlu direview manual, bisa makan
  waktu lebih lama"; a run that transitions to `approved` (was
  `flagged`) → "poin kamu sudah disetujui dan masuk leaderboard";
  `rejected` → the specific reason(s) from `anomaly_flags` translated to
  plain language, poin dibatalkan.
- Yang TIDAK dikerjakan: adding `flag_confidence` to the API response
  (already T2.12c's DoD — this task only reads what's already there);
  fetching/writing the local data this task displays (T2.14 for initial
  sync, T2.14d for later reconciliation); push notifications when a
  `flagged` run later resolves in the background — client only reflects
  current status on next screen visit/sync, no background alert
  (Could-have, out of v1 scope per product-spec §3); copy for a
  **`validated`** run whose points differ from the local estimate due to
  `trust_multiplier` or sub-`FLAG_THRESHOLD_PCT` segment exclusion —
  `trust_multiplier`'s formula/exposure is itself an open item (tech-spec
  §2.2/§2.4), tracked as a known gap in the AC 4.3.2 matrix row
  (tasks/README.md) rather than solved here.

**Depends on:** T2.14, T2.14d

**Reference:** [product-spec.md](../../01-product/product-spec.md) AC 4.3.2,
[tech-spec.md](../../02-architecture/tech-spec.md) §2.4.1, §3 step 5,
[database-api-spec.md](../../02-architecture/database-api-spec.md) §2.2

**Definition of Done:**
- [x] Run summary/history entry displays status-appropriate,
      human-readable copy for `flagged` (low and high, differentiated),
      `approved`, and `rejected` — never just the raw status string.
      `RunStatusCopy` (`ios/Laju/Models/RunStatusCopy.swift`, pure) +
      `RunHistoryRow` in `RunHistoryView`. Unit-tested per combination
      (`RunStatusCopyTests`) and **seen rendering in the iPhone 17 Pro
      Simulator** with 4 seeded runs (flagged-low, flagged-high, rejected
      with 4 flags, approved) — all four show distinct correct copy.
      *Scope note:* the post-run **summary sheet** (`RunSummaryView`) is
      built from the local `RunSummary` right at stop time, before any
      sync, so it has no server status to show; the history row is the
      persistent surface that does
- [x] Raw `anomalyFlags` codes are never shown to the user directly —
      always translated via the lookup table
      (`testEveryKnownFlagFamilyTranslatesAndNeverLeaksTheRawCode` —
      asserts no raw code and no `_` in any message; an unknown/future
      code falls back to "Ada pola lari yang tidak biasa" rather than
      leaking; the Simulator run included a made-up `brand_new_check`
      and showed the generic line). Multiple segment flags of one family
      collapse to one reason
- [x] Reopening the app / next sync after a background resolution
      (`flagged`→`approved` or `flagged`→`rejected`) reflects the updated
      status and copy — powered by T2.14d, not by anything internal here
      (`testCopyFollowsTheStoredRowThroughAFlaggedToApprovedResolution`;
      in the Simulator, rewrote two stored rows `flagged`→`approved` /
      `rejected` the way T2.14d does, relaunched, and both rows showed the
      new copy). `RunHistoryRow` now uses `@ObservedObject` so a row also
      re-renders on an in-process attribute change

**Known UX gap found while verifying (not fixed — outside this task):**
a `rejected` row still shows the *local estimate* ("80.0 pts", accent
colour) next to "Poin dibatalkan", because T1.5's row shows
`estimatedPoints` (and its DoD, AC 4.18.2, says displayed values match
Core Data). The user reads "80 pts" and "points cancelled" together. Needs
a product call: show `finalPointsAwarded` (0) for synced runs instead, or
strike-through the estimate. Left as-is rather than silently changing T1.5's
verified behaviour.

iOS suite 124/124 (116 + 8 `RunStatusCopyTests`), `swiftlint --strict` and
`swiftformat --lint` clean.

---

### T2.18 — LeaderboardEntry precompute job (global scope)

**Objective:** Build the precompute mechanism architecture.md §4
prescribes — leaderboard reads must never aggregate live.

**Scope:**
- Yang dikerjakan: Vercel Cron job reading `PointTransaction` (scoped to
  active season) **from runs with `RUN.status` `validated` or `approved`
  only** (tech-spec.md §2.4.1 — `flagged`/`rejected` excluded), **and
  excluding any user with `deleted_at IS NOT NULL`** (database-api-spec.md
  §2.1b, added 2026-09-13 Round 7 finding B7-12/B7-P4), writing
  `LeaderboardEntry` rows for `scope_type=global` only (each row's
  `frozen_display_name` set from `User.display_name` at write time — a
  denormalized snapshot, not a live join, database-api-spec.md §1), the
  job **rebuilds** the full entry set per run (not an incremental upsert)
  so a newly-soft-deleted user is naturally excluded from the very next
  run without needing a separate removal step, indexed per
  architecture.md §4. Also writes/updates the single `LEADERBOARD_SCOPE`
  row for `scope_type=global` (`scope_id='GLOBAL'` sentinel — NOT NULL,
  `insufficient_data=false` hardcoded, `user_count`, `computed_at`) —
  `global` is an explicit scope value in that table from this task
  onward, not an absent row (database-api-spec.md §1).
- Yang TIDAK dikerjakan: per-region scopes (kecamatan/kabupaten_kota/
  provinsi) — that's T3.2, explicitly deferred (Fase 3 until 2026-09-21;
  now CANCELLED PERMANENTLY 2026-09-22 together with the whole Local Leaderboard — was "Fase 4 / v1.1 deferred"; see
  phase-4-backlog.md).

**Depends on:** T2.12b, T2.17

**Reference:** [architecture.md](../../02-architecture/architecture.md) §4,
[database-api-spec.md](../../02-architecture/database-api-spec.md) §1

**Definition of Done:**

**Design decision (user-approved 2026-09-19):** scheduled with **`pg_cron`
inside Supabase**, not Vercel Cron as the Scope literally says. Vercel's
Hobby plan rejects anything more frequent than daily (OPS-1), which cannot
meet "≤15-minute interval" / AC 4.5.2. The job is one SQL function,
`rebuild_global_leaderboard()` (migration
`20260918201334_leaderboard_global_precompute.sql`), so the delete+insert
runs in a **single transaction** — a reader never sees an empty or
half-rebuilt board, which a multi-call TypeScript job could not guarantee.
Serialized with `pg_advisory_xact_lock`; `EXECUTE` revoked from
`anon`/`authenticated` (Supabase would otherwise expose it as a public RPC).

- [x] Job runs on a ≤15-minute interval and correctly ranks all users by
      total points in the active season — `cron.job` row
      `rebuild-global-leaderboard`, `*/15 * * * *`, active; **observed a
      real scheduled execution** (`cron.job_run_details`: 20:15:00 UTC,
      `succeeded`), not just a manual call. Ranking verified by
      `leaderboard.integration.test.ts` (real DB): points summed per user,
      ties share a rank (`rank()`, so 300/300/100 → 1/1/3)
- [x] `LeaderboardEntry` indexed on `(season_id, scope_type, scope_id,
      points DESC)` — `leaderboard_entry_rank_idx`; `EXPLAIN ANALYZE` of
      the top-50 read shows an Index Scan, 0.108 ms at 5000 rows
- [x] A `LEADERBOARD_SCOPE` row for `scope_type=global` exists after the
      first run, `insufficient_data=false` — confirmed live
      (`GLOBAL`, `user_count`, `computed_at`) and asserted in the test
- [x] A `flagged` run's points do not appear; they **do** after it
      resolves to `approved` on the next run; a `rejected` run never
      appears — one test walks that sequence (flagged 500 → absent; set
      `approved`, rebuild → 500; a rejected run with its T2.12b
      compensating `adjustment` row contributes nothing)
- [x] A soft-deleted user never appears after the first job run following
      deletion (present → set `deleted_at` → rebuild → absent)
- [x] Job execution time well within 15 minutes at test volume — 5000
      users / 25,000 runs / 25,000 ledger rows (seeded inside a
      transaction, rolled back, 0 leftover): **389 ms**

Also asserted: a full rebuild (two runs never duplicate rows),
`frozen_display_name` is a snapshot (changing `display_name` does not
change the entry until the next rebuild; falls back to `username` when
`display_name` is null), and `anon` cannot call the function.

Not done here, by scope: the trust-threshold filter ("users below the trust
threshold do not appear") is **T2.19's** DoD (a read-time filter), and
`streak_bonus` transactions with no `run_id` (a later feature) would need
the inner join to `run` revisited when that ships. Backend suite 150/150
(145 + 5), `tsc`/`eslint` clean; no Vercel deploy needed (no app code
changed). First CI run had 1 of the 5 fail with `TypeError: fetch failed` on
the first request (a runner transport blip, 44 ms, before any response; the
other 4 passed, local passed) — the test setup now retries *only* that
transport error (`retryTransport`), so real DB/logic errors still fail
immediately.

---

### T2.19 — GET /api/leaderboard endpoint (global scope)

**Objective:** Expose the precomputed global leaderboard to clients.

**Scope:**
- Yang dikerjakan: endpoint per database-api-spec.md §2.4, `scope=global`
  only for this task (region filters are T3.4 — CANCELLED PERMANENTLY 2026-09-22, was deferred to Fase 4 / v1.1,
  phase-4-backlog.md).
- Yang TIDAK dikerjakan: region-scoped queries.

**Depends on:** T2.18

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §2.4

**Definition of Done:**

**Decisions made here (user-approved 2026-09-19):** the low-trust cutoff is
**`trust_score < 0.5` hidden** (≈ 5 net HIGH flags in the 30-day window;
tech-spec defined the formula but never the cutoff). It is applied in the
**precompute** (migration `20260918202558_leaderboard_hide_low_trust.sql`,
one constant `v_min_trust`), not at read time, so `rank`, `me.rank` and
`leaderboard_scope.user_count` agree — a read-time filter over an
already-ranked board would leave gaps (1, 2, 4 …) and make a caller's own
`me.rank` disagree with the list they see. Consequence: a trust change takes
effect on the next 15-minute rebuild, and a hidden caller gets `me: null`.

- [x] Response matches database-api-spec.md §2.4 example shape (`entries`,
      `me`, `computed_at`) — deployed; live response verified:
      `{season_id, scope:"global", scope_id:null, computed_at,
      insufficient_data:false, entries:[{rank,user_id,username,points}],
      me:{rank,points}}`. `username` carries the T2.18 `frozen_display_name`
      snapshot; `scope_id` is `null` for global (the `'GLOBAL'` sentinel is a
      storage detail, not exposed). Unit test asserts the exact shape
- [x] p95 response time < 300ms, reading the precomputed table — **only
      after a fix outside this endpoint's code.** First live measurement was
      **2–3 s** (vs `/api/health` ≈ 0.3 s from the same machine): Vercel ran
      the functions in **iad1 (US East)** while Supabase is **ap-southeast-1**,
      so each of the ~4 sequential DB round-trips crossed the Pacific
      (`x-vercel-id: sin1::iad1`). Pinned `"regions": ["sin1"]` in
      `vercel.json` → `sin1::sin1`; re-measured, **n=100 warm requests, client-
      observed round trip: median 135 ms, p90 176, p95 204, p99 352, max 668**
      (one cold-instance outlier pair early on). Queries are index-backed
      (`leaderboard_entry_rank_idx`, T2.18) and the three reads run in parallel
- [x] Users below the trust threshold (T2.11) do not appear in results —
      `route.integration.test.ts` (real DB + genuine Auth JWT): a user at 0.49
      with 200 points (would rank 2nd) is absent, one at exactly 0.5 is
      present, ranks are self-consistent, `me` matches; a caller pushed to
      0.4 drops off the board and gets `me: null`. Re-verified against the
      deployed endpoint (900-point user at 0.3 not returned)

Also: `scope` required; region scopes → 400 (T3.4); `limit` 1–100
(default 50); `season_id` must be a UUID (the spec example's
`season_2026_q3` string does not match the real UUID ids); unknown/no
active season handled; `me`/entries never trigger a live aggregation
(unit-asserted). Backend suite 171/171 (150 + 16 unit + 5 integration),
`tsc`/`eslint` clean.

**Side effect worth knowing — PERF-1:** that region fix applies to every
route, including `POST /api/runs`, whose measured p95 of 7.8 s (T2.12e) was
attributed to "~9 sequential Supabase round-trips". At ~230 ms per
trans-Pacific hop that is exactly the shape of this problem. **PERF-1 is not
closed** — no load test was re-run — but it is now very likely much smaller
and needs re-measuring before the T2.21 gate. Also found: `fileParallelism:
false` added to `vitest.config.ts`, because integration files share one real
database and one global leaderboard and were seeing each other's test users
in their rankings.

---

### T2.20 — Global leaderboard screen on mobile

**Objective:** Ship the user-facing feature this phase has been building
toward.

**Scope:**
- Yang dikerjakan: screen consuming `GET /api/leaderboard?scope=global`,
  showing top N + the current user's own rank even if outside top N
  (product-spec AC 4.5.1).
- Yang TIDAK dikerjakan: region filter UI (T3.5 — CANCELLED PERMANENTLY 2026-09-22, was deferred to Fase 4 / v1.1, phase-4-backlog.md).

**Depends on:** T2.19

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.5

**Definition of Done:**
- [x] Top N entries and the user's own position both render correctly —
      `LeaderboardView`/`LeaderboardContent` (new **Ranks** tab in
      `RootTabView`, the `social` slot reserved for this task). `me` comes
      from the server separately from the top-N list, so the caller's rank is
      shown even when outside it (AC 4.5.1): decoded from a live-shaped
      response with `me.rank 47` against a 2-entry list
      (`testDecodesLiveShapedResponse...`), and **the real SwiftUI view was
      rendered to an image and looked at** (`ImageRenderer` → PNG): a
      "Posisi kamu #47 / 120 pts" card above a top-6 list, top 3 in accent.
      `me == nil` (no counted points, or hidden for low trust — deliberately
      indistinguishable) shows "Belum masuk leaderboard — selesaikan run
      untuk mendapat poin"; an empty board and a `null` username have their
      own copy. **Not seen with real data on a device/Simulator:** that needs
      a signed-in session (Sign in with Apple, Apple Developer Program). In
      the Simulator, signed out, the tab shows the failure state ("Tidak bisa
      memuat leaderboard" + "Coba lagi") — verified, no broken layout
- [x] Data staleness shown, consistent with the ≤15-minute precompute target
      — "Diperbarui 7 menit lalu" from the server's `computed_at`
      (`LeaderboardFreshness`); past 20 min (15 + slack) the line turns
      warning-coloured and adds "data mungkin belum terbarui", so a stalled
      cron job is visible rather than silently presenting an old board as
      current. `computed_at` arrives with **microseconds** from PostgREST —
      the shared decoder fallback added in T2.14d handles it (test uses the
      real shape)

Also: last good board is kept when a later refresh fails (banner "Gagal
memperbarui — menampilkan data terakhir"), pull-to-refresh, signed-out
never touches the network. Request is `scope=global&limit=50` + Bearer,
asserted. iOS suite 134/134 (124 + 10 `LeaderboardTests`), `swiftlint
--strict`/`swiftformat --lint` clean.

**Test-environment finding:** `RunViewModelPersistenceTests
.testPeriodicFlush...` started failing (2 points instead of 1) — the
Simulator had kept the app's location permission from an earlier session, so
the real simulated location slipped in as a second point. Not a code
regression: it failed deterministically until `simctl privacy booted reset
location com.designbyripo.laju`, then passed. If it reappears locally, that
reset is the fix.

---

### T2.20a — API rate limiting (SEC-9) — out-of-band, added 2026-09-19

**Objective:** Close [security-review.md](../../04-quality-security/security-review.md)
SEC-9 — rated **Blocker for Fase 2** — and SEC-10, its multiplier. Nothing in the
backend limits how often, or how expensively, a caller may hit it: `POST
/api/runs` is the costliest endpoint (synchronous anti-cheat over the whole
route + ≈9 DB round-trips) and the Fase 2 audit measured the ceiling it can
absorb — **≈25 submissions/s** before every request queues (T2.12e). One
abusive or buggy client can therefore use up the shared capacity for everyone,
and on a serverless platform every invocation is also money. The only throttle
that exists today is the client-side 15-minute reconciliation rule, which
`database-api-spec.md` §2.2b itself labels "not enforced server-side in v1".
Numbered `T2.20a` (out-of-band, same pattern as `T2.0a`) so no existing task
is renumbered; it sits before the gate because SEC-9 states rate limiting
"belongs in that same gate".

**Approach (decided here; the numbers are starting values to tune, not spec):**

1. **Where it runs — Postgres, inside the stack that already exists.** A table
   `rate_limit_bucket(key text, window_start timestamptz, count int, primary
   key (key, window_start))` plus one SQL function `rate_limit_hit(key, limit,
   window_seconds)` that upserts and increments **atomically** and returns
   `(allowed, retry_after_seconds)`. Called from a small wrapper in
   `lib/` that every route uses. Chosen over: *in-memory limiting* (each
   serverless instance has its own memory — a limit that resets per cold start
   is no limit); *Upstash/Redis* (a new vendor and new failure mode for a
   problem one indexed table solves at this scale; `architecture.md` §4 already
   argues against adding infrastructure before it is needed); *Supabase Auth's
   own limits* (they protect sign-in, not our endpoints).
2. **Two keys, two layers.** *Per user* (`user.id`, applied after auth) is the
   real control — it is what stops a signed-in client. *Per IP* (`x-forwarded-for`,
   applied **before** any auth call) protects the auth-verification hop: an
   unauthenticated flood costs one Supabase Auth request per call, so it must be
   refused before that. If Vercel's platform-level WAF rate-limit rule is
   available on the plan in use, put the coarse per-IP rule there (refused at
   the edge, no function invocation) and keep the in-function limiter as the
   per-user layer; otherwise the same Postgres limiter does both.
3. **Starting limits** (per key; legitimate patterns are 1–5 runs/day, but a
   device that was offline for weeks legitimately uploads a backlog — the
   test device holds 127 queued runs — so the run limit must tolerate a burst):
   `POST /api/runs` 30/min and 300/h per user; `GET /api/runs` (reconciliation)
   30/h; `GET /api/leaderboard` and `GET /api/users/me/progress` 60/min;
   `POST /api/profile/complete` 10/h; `DELETE /api/account` 3/h; per-IP 120/min
   across `/api/*`. `/api/cron/*` is not limited (secret-gated) and `/api/health`
   only by the per-IP layer.
4. **Contract:** `429` with a `Retry-After` header and body `{"error":
   "rate_limited","retry_after_seconds":N}`. The client already treats 429 as
   recoverable (T2.14b's classification); it must additionally **stop the current
   batch** on a 429 rather than keep firing the rest of a 127-run backlog.
5. **Bound the cost of one request (SEC-10, closes here).** Reject a `gps_route`
   over a fixed point count (starting value 20,000 — a marathon at 1 point/s is
   ≈14,400) and a body over a fixed size, with `413`/`422`, *before* any anti-cheat
   work. SEC-10 states the two compound and "neither alone is sufficient".
6. **Failure mode:** if the limiter itself errors (database unreachable), **fail
   open and log** — the rest of the request would fail anyway, and a limiter must
   not become the reason a healthy request is refused. Expired buckets are
   deleted by a `pg_cron` job so the table cannot grow without bound.

**Scope:**
- Yang dikerjakan: the bucket table + `rate_limit_hit` function (migration, RLS on
  with no policies, like every table since 2026-09-19), the `lib/` wrapper, wiring
  into all 8 routes, the payload cap, the cleanup job, the client-side stop-batch
  on 429, and recording Supabase Auth's actual rate-limit values (they are
  inherited defaults, not decisions — SEC-9 exposure 2).
- Yang TIDAK dikerjakan: CAPTCHA / bot detection; per-device fingerprinting;
  reputation or auto-ban; making the anti-cheat cheaper; raising the 25/s ceiling
  itself (that is T2.12e's accepted limitation, pending the Supabase upgrade).

**Depends on:** T2.5, T2.14c, T2.15, T2.19, T2.22 (all the endpoints it wraps
must exist), T2.12e (its measured ceiling is what the run limits are sized against)

**Reference:** [security-review.md](../../04-quality-security/security-review.md) SEC-9, SEC-10,
[database-api-spec.md](../../02-architecture/database-api-spec.md) §2.2b, §3,
[tech-spec.md](../../02-architecture/tech-spec.md) §4

**Definition of Done:**
- [x] Every endpoint in `database-api-spec.md` is covered by the per-user layer
      (or documented as exempt with the reason), and every request is covered by
      the per-IP layer before auth is called — the per-IP layer lives inside
      `requireAuthenticatedIdentity`, ahead of the Auth call, so no route can omit
      it; each route passes its own rule name (`runs.post` 30/min + 300/h,
      `runs.get` 30/h, `leaderboard.get`/`progress.get`/`seasons.active`/`auth.me`
      60/min, `profile.complete` 10/h, `account.delete` 3/h); `/api/health` is
      per-IP only; `/api/cron/resolve-flagged-runs` is exempt (secret-gated, called
      by Vercel Cron only). `rate-limit.test.ts` walks every `route.ts` and fails
      if a new route ships without a rule
- [x] Exceeding a limit returns `429` + `Retry-After` and the documented body;
      the window resets and requests succeed again afterwards — tested against
      the real database (`rate-limit.integration.test.ts`: a burst of 5 against a limit of 3 in a 6 s
      window → 3 allowed, 2 refused with Retry-After 1–6 s, allowed again after the
      window; first version of this test used a 2 s window and flaked on a slow CI
      round-trip, hence the longer window)
- [x] **Atomic under concurrency:** 40 simultaneous calls against a limit of 10 let
      exactly 10 through, 30 refused (real database, `rate_limit_hit`'s upsert takes
      the row lock)
- [x] **Per-key isolation:** one user exhausting their limit does not limit
      another user, an IP, or the same user on another route (test), and live: user
      A refused while user B on the same IP was not
- [x] `POST /api/runs` rejects an over-cap `gps_route` (> 20,000 points) and a
      declared body > 4,000,000 bytes with `413` before anti-cheat runs (SEC-10) —
      `payload-cap.integration.test.ts`, no run row written; a route of exactly
      20,000 points still passes the cap (it took ≈6.8 s through anti-cheat locally,
      i.e. the cap bounds one request's worst-case cost)
- [x] The limiter's own overhead on `POST /api/runs` is measured and reported: one
      `rate_limit_hit` round-trip is median 60 ms / max 80 ms from this machine and
      the request makes two (IP + user) — yet 20 sequential live calls measured
      median 428 ms / p95 478 ms, inside the 463–561 ms range before the limiter, so
      the cost is not distinguishable from run-to-run noise. A limiter failure fails
      open with a log (`rate-limit.test.ts`, both an RPC error and a thrown network
      error)
- [x] Client: a `429` stops the current sync batch and the runs stay queued
      (`SyncRateLimitTests`, 4 tests: 5 queued runs → 1 request; mid-batch refusal
      keeps the 2 already-synced and stops; the backlog goes through on the next
      cycle once the limit lifts; 429 is not a permanent rejection). Supabase Auth's
      actual values are recorded in `security-review.md` SEC-9 — **inferred, not read
      directly:** `supabase config diff` against the live project reports no
      difference in `auth.rate_limit`, so the remote equals the CLI defaults listed
      there (sign-in/up 30 and OTP/magic-link 30 per 5 min per IP, token refresh 150
      per 5 min per IP; email/SMS/anonymous now unused, the email provider being off)
- [x] Deployed and verified live (production, `6bea1a8`): 130 concurrent requests
      to `/api/health` → exactly 120 × `200` then 10 × `429` with `retry-after` and
      the documented body; a real Auth JWT posting to `/api/runs` 35 times → 30
      passed the limiter and 5 × `429` (retry-after 37); a second user on the same IP
      was unaffected; `verify-release.ts` 7/7 and health `200` afterwards

**Status: DONE 2026-09-21** (commit `6bea1a8`, plus `6f4528b` which made two
timing-sensitive integration tests robust after the first CI run failed on them —
a slow runner let a 2 s window and a 60 s window roll over mid-test; the limiter
itself was not at fault. CI Backend green on `6f4528b`, CI iOS green on `6bea1a8`.
Backend 219/219; iOS 159/159 locally, of which 8 belong to the separate, not yet
committed map-animation work (`MarkerTweenTests`), so CI counts 151). Migration
`20260921120000_add_rate_limiting.sql` applied via `supabase db push`: table
`rate_limit_bucket` (RLS on, no grants to `anon`/`authenticated`), function
`rate_limit_hit` (execute only for `service_role`, checked with
`has_function_privilege`), pg_cron job `cleanup-rate-limit-buckets` every 15 min.
Vercel's platform WAF rate-limit rule was **not** used (not available on the
Hobby plan) — the Postgres limiter does both layers. Known limits, accepted:
fixed windows (a burst can straddle a boundary, up to 2× the limit for an instant),
and a request with no client address (direct calls, tests) skips the per-IP layer.

---

#### Real client–server chain — verified 2026-09-21 (Simulator, real Supabase session, no Sign in with Apple)

**Why this exists.** T2.14, T2.16, T2.14d and T2.20 were checked `[x]` with the network stubbed and no signed-in session
(Sign in with Apple needs the paid Apple Developer Program; the Simulator attempt failed with `AKAuthenticationError
-7022` / `AuthorizationError 1000`, an Apple-side rejection of the bundle ID). This run replaces the stub with the real
thing on everything except the sign-in step.

**Method.** A throwaway real Supabase user (Admin `createUser` → `generateLink` → `verifyOtp`, i.e. a token Supabase
itself issued) and a `user` row with region inserted via `service_role` — a *substitution for the client half of T2.4*,
which is not built (the app never calls `POST /api/profile/complete`). The session was injected into a **Debug-only**
`AuthService.init` hook (`#if DEBUG`, launch-environment tokens; not committed, not in Release). Then, in the iOS
Simulator against the deployed production API: simulated GPS route (`simctl location start`, 3 m/s), Start → run →
Finish through the real UI, real `SyncService`, real `ReconciliationService`, real Profile and Ranks screens.

**Evidence.**
- **Recording:** 0.65 km / 3:57 / pace 6:03 and 0.58 km / 3:39 / pace 6:19, live map + route line, Run Summary with
  splits, streak, points estimate (+2.7).
- **Upload (T2.14):** the app's own request reached `POST /api/runs`; server row `validated`, 651.9 m, `duration_seconds`
  237, 44 route points, `point_transaction` +1, `user.total_points` 1; the local Core Data row became `synced` with a
  `serverRunId` identical to the server's `run.id` and `finalPointsAwarded` 1.0.
- **Reconciliation (T2.14d):** *arranged state* — the synced run was set to `flagged`/LOW on the server and in the local
  store, then rejected with the real manual-override tool (`resolve-flagged-run.ts … rejected`: server `rejected`,
  compensating −1, `total_points` 0). The app then caught up **by itself** on its next cycle: local `serverStatus`
  `rejected`, points 0.0, `resolvedAt` set, `SyncMeta` attempt time and cursor recorded. The flagged state itself could
  not arise from the simulated GPS (the client filters it out before upload), hence arranged.
- **Progress (T2.16):** the Profile screen showed **1 total point, Level 1, 99 to next level** — the server's value, not
  the ≈5 the local estimates would sum to, so the server branch is live. The offline fallback was already confirmed.
- **Leaderboard (T2.20, T2.18, T2.19):** after `rebuild_global_leaderboard()` the Ranks screen showed the user's row and
  "Posisi kamu #8 · 1 pts, diperbarui 1 menit lalu" from the real endpoint.

**A real defect this found (fixed — commit `d973ce0`).** The very first real upload failed: `POST /api/runs` → `500 Could
not save run`. Cause: `run.duration_seconds` is an `integer` column, the client measures a real elapsed time (Core Data
`Double`, e.g. 236.83 s) and the route wrote it raw. **Every run from the real app would have failed to sync, forever**
(the app retries a 500, correctly, so it never surfaced as a rejection) — including the 127 queued runs on the test
device. It stayed hidden for the whole of Fase 2 because every test used whole seconds or a stubbed network. Fixed by
rounding at the API boundary (0 s after rounding → `400`); regression test `duration-rounding.integration.test.ts`
(fails with a `500` without the fix, passes with it). Confirmed against production afterwards: the same run then syncs.

**Second defect, in my own test code (fixed — `f771a3f`).** `payload-cap.integration.test.ts` deleted `run` before
`point_transaction`; the foreign key made that fail silently and left **seven test users on the real global
leaderboard** (2 points each). Found only because this run looked at the leaderboard. Cleaned from production and the
test fixed; production now holds no test data (0 users / runs / leaderboard rows after this run's own cleanup).

**Findings from that run — the two product ones FIXED the same day (2026-09-21).**
- **Server awarded no streak bonus — FIXED (`7151bf3`, `b21c62f`).** `POST /api/runs` used to compute points with
  `streakDays = 0`, so any run with a streak ≥ 1 was awarded less than the client's own estimate, silently (estimate
  +2.7, awarded 1). The server now derives the streak from the user's own run history (`lib/streak.ts`: consecutive
  Asia/Jakarta calendar days ending yesterday with a `validated`/`approved`/`flagged` run of ≥ 100 m, plus today's
  run if it qualifies — the client's `StreakTracker` semantics; a `rejected` run does not extend a streak, and the
  client can not assert one: the request's `streak_days` is ignored). Tests: 10 unit + 6 real-database integration
  (no history, 2 consecutive days, a gap, a rejected day, a sub-100 m day, the 7-day cap) + a route test — the
  integration ones fail on the old code with exactly `expected 1 to be 3`. **Verified live on production:** the client
  estimate 2.58 (`+2.6`, "1 day" streak) → server `final_points_awarded` 3, ledger +3. Assumption: day boundaries
  are WIB (UTC+7) because the server does not know the device's timezone — see tech-spec.md §2.2.
- **The app never called `POST /api/profile/complete` — FIXED (`8002079`; backend `profile_missing` code in
  `7151bf3`).** A new onboarding step (username + kecamatan + kabupaten/kota + provinsi) sits between sign-in and the
  location prompt; after sign-in the app asks `GET /api/auth/me` and shows it only when the server answers the new
  `401 {"code":"profile_missing"}` (a returning account skips it). **Verified live on production, no seeding:** a real
  Supabase session with no `user` row → the app showed the step → the filled form created the row
  (`e2e_runner`, Kebayoran Baru / Jakarta Selatan / DKI Jakarta) → the first run synced. Caveats: (1) **region is free
  text** — no catalog exists (thousands of kecamatan), so the same place can be spelled several ways; the deferred
  Local Leaderboard must normalize it, and T3.1's cascading picker replaces these fields; (2) the first version treated
  *every* token error as "nobody signed in" and skipped the step on a dropped connection — caught by a real network
  blip during this very test, fixed (only `sessionMissing` means skip; anything else shows the step) and pinned by a
  test; (3) usernames are not unique in the schema — nothing enforces it.
- **A stale Apple ID in the Simulator's Settings raises "Apple Account Verification" prompts** over the app. Environment
  noise, dismissed with "Not Now"; no credential was entered by the assistant.

**Repeated 2026-09-21 with a REAL sign-in — Google, no injected token.** Google Sign-In was added the same day
(product-spec.md §4.1 AC1, tech-spec.md §6) precisely because it needs no paid Apple entitlement. The whole cycle was
run again, this time through the real button:
- **Sign-in (T2.3):** the user tapped *Sign in with Google* in the Simulator and signed in with their own Gmail; server
  side `auth.identities` gained exactly one `google` identity (`auth.users.raw_app_meta_data.provider = google`). The
  OAuth PKCE exchange through `ASWebAuthenticationSession` and the redirect back to `com.designbyripo.laju://auth-callback`
  therefore work end to end. (The first attempt was cut short by the Simulator shutting down — `signal 9` — before any
  session formed; nothing was wrong with the code or the Google/Supabase configuration.)
- **Run → upload (T2.14):** real GPS-simulated run 0.58 km / 3:39 / 6:18 per km → server `validated`, 578.6 m,
  `duration_seconds` 237, 50 points, ledger +1; local row `synced` with the server's `run.id`. A stray earlier tap of
  Start/Stop (0 m, 4 s, one point) was refused by the server with `400` and became `rejectedPermanent` locally — the
  4xx classification (`b32c409`) confirmed on a real occurrence of the exact pattern behind 69 of the 127 runs on the
  test device.
- **Progress (T2.16):** Profile showed the server's 1 point, Level 1, 99 to next level.
- **Leaderboard (T2.20):** after `rebuild_global_leaderboard()` Ranks showed **#1 · 1 pts · "E2E Google"**, "diperbarui
  baru saja".
- **Reconciliation (T2.14d) and session persistence (AC 4.1.3):** flagged state arranged as before, run rejected with
  the real override tool, then the app was **force-quit and cold-launched with no token of any kind** — it was still
  signed in (the session survived in the Keychain) and reconciled by itself: local `rejected`, points 0, `resolvedAt` set.
- All test data, including the Google test identity, was removed from production afterwards (0 users / runs /
  leaderboard rows).

**Still NOT verified.** Sign in with **Apple** itself — the nonce question (the button sets none) and the
`signInWithIdToken` exchange — and everything needing a real device or the Apple Developer Program. T2.21 stays open.

### T2.21 — Phase gate: confirm anti-cheat verified before enabling public global leaderboard

**Objective:** Enforce, as an explicit checklist item, the hard dependency
stated in development-plan.md — this task exists so the ordering
constraint cannot be silently skipped under schedule pressure.

**Scope:**
- Yang dikerjakan: go/no-go check confirming T2.13 (anti-cheat
  verification) passed and is deployed to the same environment as the
  leaderboard release; only then is T2.20 released/enabled to real users
  (feature flag off until this check passes, if a release happens before
  T2.13 fully lands).
- Yang TIDAK dikerjakan: any new code — this is a release-gate checklist,
  not a build task.

**Depends on:** T2.13, T2.20, T2.14, T2.16, T2.14b, **T2.20a** (SEC-9 rate limiting — added 2026-09-19; Fase 2 cannot be closed without it)

**Reference:** [development-plan.md](../development-plan.md) Fase 2 hard
dependency ("anti-cheat must ship and be verified before the global
leaderboard is made visible")

**Definition of Done:**

**Gate evaluated 2026-09-19 — result: NOT PASSED (3 of 7 items met; 4 open). An 8th item — SEC-9 rate limiting, owned by T2.20a — was added afterwards (Fase 2 audit) and is also open.**
All dependencies (T2.13, T2.20, T2.14, T2.16, T2.14b) are done, so the gate
*can* be assessed; it cannot be signed off. Nothing below was checked without
evidence, and the open items are open for real reasons, not paperwork.

- [x] T2.13's test suite is green in the production/release environment,
      not just locally — two independent pieces of evidence. (1) CI runs the
      suite against the real Supabase project on every push (green, e.g.
      run 35401153603's backend counterpart 35397316992). (2) **New:**
      `backend/scripts/verify-release.ts` runs T2.6b's fixture corpus against
      the **deployed** backend (`https://backend-eight-gules-56.vercel.app`)
      over real HTTP with a genuine Supabase Auth JWT — T2.13's own tests
      call the route handlers in-process, so this is the part that was never
      exercised in the release environment. Result: **7/7 PASS** — both
      negative controls `validated` with zero flags; `pace-cap-breach`,
      `gps-speed-jump`, `teleport`, `combined-anomalies` each rejected with
      their own flag family. Re-runnable: `npx tsx --env-file=.env.local
      scripts/verify-release.ts` from `backend/`
- [x] Leaderboard feature flag (if used) confirmed enabled only after the
      above — **no flag was used**, so this reduces to ordering, which held:
      T2.13 was signed off 2026-09-18, the leaderboard endpoint/screen
      (T2.19/T2.20) were built 2026-09-19, and the app has no external
      distribution yet (no Apple Developer Program → no TestFlight), so no
      real user could have seen the board before the check
- [ ] **OPEN** — Offline sync (T2.14) and server-backed progress (T2.16) both
      verified working, not just the leaderboard. Logic is covered (SyncService
      8 tests, ProgressViewModel 5 tests, stubbed network + fake connectivity),
      and every backend endpoint they call is live-verified. What has **never**
      run is the real chain — a real device, signed in, recording offline,
      reconnecting, pushing to the real backend — because it needs a Supabase
      session and Sign in with Apple is blocked on the Apple Developer Program.
      Same gap already tracked in `deferred-manual-tests.md`
- [ ] **OPEN** — "Visible reason" clause verified end to end. Each link is
      verified separately (backend flag→resolve→`GET /api/runs`: T2.13/T2.14c
      live; client copy T2.14b: seen in the Simulator with seeded rows;
      reconciliation T2.14d: 12 tests + a live check of the server's real
      response format). Not done: one real flagged run, resolved in the
      background, appearing in the app — same signed-in-device blocker
- [x] T2.22 (account deletion) is explicitly tracked as an App Store
      submission gate separate from this gate — `pre-launch-checklist.md` §4
      ("Account Deletion (Guideline 5.1.1(v))": T2.22 verified end-to-end,
      "**this blocks submission entirely**"). T2.22 itself is **not built
      yet** — it is the next task
- [ ] **OPEN** — Every Fase-2 row in `deferred-manual-tests.md` is Pass or an
      explicitly accepted limitation. Three Fase-2 rows are outstanding, none
      Pass, none yet accepted: **T2.3** Sign in with Apple round-trip
      (blocked: Apple Developer Program), **T2.0a** tab-bar rendering on the
      deployment target (iOS 26 vs 16 artifact), **T2.14** offline→online over
      a real network. This needs a decision from the owner: run them, or
      record each as an accepted limitation with a reason
- [x] **DONE 2026-09-21 (added 2026-09-19)** — SEC-9 API rate limiting is implemented and
      verified live (T2.20a, commit `6bea1a8`). `security-review.md` rates it **Blocker for Fase 2**
      and states rate limiting "belongs in that same gate"; it had no owning task
      and was missing from this list until the Fase 2 audit found it. The backend
      is publicly reachable, so this is not a future concern
- [ ] **OPEN** — Sign-off recorded. Not recorded: four items above are open,
      and sign-off is the owner's call, not something to infer

**What changed the picture while running this gate — PERF-1 partly resolved (corrected later the same day: see T2.12e).**
`verify-release.ts` also times `POST /api/runs`: **20 sequential calls,
median 385 ms, p95 463 ms, max 489 ms** against tech-spec.md §4's 1.5 s budget
(T2.12e had measured p95 7.8 s). The cause was the Vercel-region mismatch found
in T2.19 (functions in iad1, database in Singapore; ~230 ms × ~9 sequential
round-trips), fixed by pinning `sin1`. That covers the *sequential* budget only. The 100-concurrent budget T2.12e actually names was re-measured in the Fase 2 audit and still fails (p95 3,827 ms) — so PERF-1 **does** still bear on this gate.

---

### T2.22 — Account deletion (App Store submission blocker)

**Objective:** Added 2026-09-12, product-spec.md §4.17 — App Store
Guideline 5.1.1(v) requires in-app account deletion for any app offering
account creation. **This is a release blocker independent of T2.21's
leaderboard/anti-cheat gate** — App Store submission cannot proceed
without it once auth exists, regardless of leaderboard readiness. Not
optional, not deferrable to a later phase.

**Scope:** (expanded 2026-09-13, Round 7 findings B7-9/B7-10/B7-11/B7-13/B7-14
— the 2026-09-12 draft only covered the server soft-delete itself, not the
client-side wipe or the auth-rejection/anonymization completeness the
feature actually needs)
- Yang dikerjakan: in-app flow to initiate account deletion (no requiring
  the user to email/use a web form), an explicit confirmation step before
  final execution, and `DELETE /api/account`
  (database-api-spec.md §2.1b) — soft-deletes the `User` row per §2.1b's
  full field-by-field behavior (every personal field explicitly
  cleared/anonymized, not just "some" — `email`, `avatar_url`,
  `username`, `display_name`, `region_*`; `total_points`/`current_level`/
  `trust_score` retained for ledger consistency but never rendered for a
  soft-deleted user), deletes the Supabase Auth identity via
  `auth_user_id` (Admin API, service-role key, backend-only — decoupled
  from `User.id` specifically so this can never cascade into the `User`
  row itself), rejects all subsequent requests from the same identity
  (`deleted_at` check, database-api-spec.md §3), nulls `RUN.gps_route`
  for this user's runs, and terminally resolves any still-`flagged` run
  to `rejected` with a compensating transaction (tech-spec.md §2.4.1's
  existing override path) so nothing is left pending for a human
  reviewer. On the client: wipes local Core Data (`Run`, `SyncMeta`),
  the Keychain session, and local `UserDefaults` — without this, the
  device retains the deleted user's precise-location history in
  cleartext, and a fresh sign-up on the same device would upload the
  old runs under the new identity. `PointTransaction` rows are never
  rewritten or deleted (append-only ledger, tech-spec.md §4 NFR).
- **Added AC, 2026-09-23 (product-spec.md §4.23 decided #12 / AC13) —
  applies once Premium (T4.20) ships; it is not a regression of what
  T2.22 already shipped, since no subscription can exist before then:**
  if the account being deleted has an active Premium subscription, the
  deletion flow shows an explicit notice before the final confirmation:
  *"Menghapus akun tidak membatalkan langganan Apple Anda — batalkan
  terpisah lewat pengaturan App Store, atau Anda tetap ditagih untuk
  langganan yang sudah tidak bisa dipakai."* ~~What happens to that
  account's `subscription` rows is **not decided** (flagged in §4.23).~~
  **Decided 2026-09-23 (§4.23 decided #13 / AC14):** the account's
  `subscription` rows are **anonymized, never deleted** —
  `original_transaction_id` and status history kept for audit/Apple
  disputes. Mechanism still open (§4.23): null `user_id` (needs an AC6
  exception) vs keep `user_id` pointing at the already-anonymized `user`
  row — the latter is what this task's own `account-deletion.ts` does for
  `PointTransaction`.
- Yang TIDAK dikerjakan: a "pause"/"deactivate" distinct from full
  deletion (not required by the Guideline, not requested); any admin-side
  tooling for deletion requests beyond the in-app self-service flow;
  carrying `trust_score` forward across a delete-then-re-register cycle
  — documented as an accepted v1 risk (database-api-spec.md §2.1b point
  7), not solved here.

**Depends on:** T2.2, T2.3, T2.18

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.17,
[database-api-spec.md](../../02-architecture/database-api-spec.md) §2.1b, §3,
[pre-launch-checklist.md](../../04-quality-security/pre-launch-checklist.md)

**Definition of Done:**

**Result 2026-09-19: PARTIAL — 6 of 8 items verified, 2 open (both need a real
signed-in device / Apple Developer Program).** Deployed to
`https://backend-eight-gules-56.vercel.app`.

- [x] User can initiate account deletion entirely from within the app —
      Profile → **Hapus akun** (`ProfileView`, `LajuDestructiveButtonStyle`).
      Seen in the iPhone 17 Pro Simulator
- [x] An explicit confirmation step is required (no single-tap irreversible
      action) — a destructive `.alert` ("Hapus akun?" … **Hapus permanen** /
      Batal). Seen in the Simulator
- [x] `DELETE /api/account` soft-deletes the `User` row per every field of
      database-api-spec.md §2.1b, deletes the Auth identity via
      `auth_user_id`, leaves `PointTransaction` untouched — verified field by
      field against real rows (`route.integration.test.ts`, real DB + real
      Auth): `deleted_at` set; `email` → `deleted+<uuid>@laju.invalid`;
      `username`, `display_name`, `avatar_url`, `region_*` all null;
      `total_points`/`current_level`/`trust_score`/`id` retained; Auth
      identity gone; both original ledger rows intact + exactly one
      compensating `−50`, none deleted; `gps_route` nulled on every run. Also
      re-verified live against the deployed API
- [x] A request bearing a still-valid JWT for an already-deleted account is
      rejected — pre-deletion token → `POST /api/profile/complete` **401** and
      `GET /api/users/me/progress` **401** (test + live). **Found and fixed a
      real hole doing this:** `POST /api/profile/complete` never checked
      `deleted_at` (spec B7-10). It matters when the last step (Auth deletion)
      fails and leaves a soft-deleted row with a live JWT: without the guard
      that token re-populated `username`/`region`. The test simulates exactly
      that state, and **fails (201) with the guard removed** — run to confirm
      it has teeth
- [ ] **PARTIAL** — Local Core Data (`Run`/`SyncMeta`), Keychain session and
      `UserDefaults` are cleared, and a fresh sign-up on the same device sees
      zero pre-existing runs. `AccountDeletionService` is unit-tested against
      a real Core Data store (`AccountDeletionServiceTests`, 7 tests): both
      entities emptied, the `pendingSync` query `SyncService` uses returns 0
      (so nothing uploads under a new identity), `UserDefaults` domain
      cleared, pending notifications cleared, in-memory `ProgressViewModel`
      reset. Deliberately **server first**: a failed/offline deletion touches
      nothing local and the user stays signed in to retry (tested, and seen in
      the Simulator: signed-out → "Gagal menghapus akun … datamu masih utuh",
      both local runs still listed). **Not verified:** the real Keychain
      session clear (`auth.signOut(scope: .local)` is stubbed in tests) and an
      actual fresh sign-up — needs a real signed-in session
- [x] A `flagged` run belonging to the deleted user is resolved to
      `rejected` with a correct compensating transaction — reuses T2.12b's
      `resolveFlaggedRun`; test: `flagged` +50 → `rejected`, `resolved_via:
      manual`, `−50` adjustment; live: +30/−30
- [x] A soft-deleted user does not appear in any leaderboard precompute run
      after deletion — verified against the real `rebuild_global_leaderboard()`
      (test first proves the user *was* on the board, then absent after)
- [ ] **OPEN** — Verified end-to-end before App Store submission. Tracked as a
      blocking item in `pre-launch-checklist.md` §4 (status noted there).
      Needs the full chain on a real signed-in device

**Design notes.** The Auth identity is deleted **last**: every earlier step
is idempotent, so a partial failure leaves a state the user can retry (the
route authenticates by Auth identity alone, so a retry works even once
`deleted_at` is set); deleting the identity first would strand a
half-deleted account with no valid token. An identity that never completed
its profile can also delete its account. Current-season leaderboard rows for
a just-deleted user linger until the next ≤15-minute rebuild (per spec §2.1b
point 8, the rebuild is what excludes them).

**New finding for the release checklist:** Apple requires apps that offer
Sign in with Apple to **revoke the Apple token** when an account is deleted.
This was in neither the spec nor this task; added to `pre-launch-checklist.md`
§4 as an open item (needs the developer-program `.p8` key).

Backend 182/182 (171 + 3 route unit + 6 integration + 2 profile guard), iOS
141/141 (134 + 7), lint/format clean.

