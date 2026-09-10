# Phase 2 — Backend + Sync + Global Leaderboard

Source: [development-plan.md](../development-plan.md) Fase 2

**Hard dependency for this whole phase:** anti-cheat, including its
fixture corpus, orchestration/ledger, and resolution lifecycle (T2.6b,
T2.7–T2.11, T2.12a–T2.12f, T2.13), must ship and be verified **before**
the global leaderboard is made publicly visible (T2.20–T2.21). This is a
correctness requirement, not a nice-to-have — see development-plan.md
Fase 2.

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

**Reference:** [tech-spec.md](../tech-spec.md) §1

**Definition of Done:**
- [ ] `GET /api/health` deployed and reachable on Vercel
- [ ] Supabase project connected, credentials stored as env vars (not
      committed)

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

**Reference:** [database-api-spec.md](../database-api-spec.md) §1 (ERD)

**Definition of Done:**
- [ ] All 6 tables exist in Supabase with fields/types matching the ERD
- [ ] Migrations are version-controlled and re-runnable (not manual
      console edits)
- [ ] `User.club_id` present and nullable, no `Club` table created
- [ ] `LeaderboardScope` supports a `scope_type='global'` row using
      sentinel `scope_id='GLOBAL'` (NOT NULL) — composite PK
      `(season_id, scope_type, scope_id)` is valid since no column is
      nullable (database-api-spec.md §1)
- [ ] `Run.updated_at` column exists (`NOT NULL DEFAULT now()`),
      maintained by a **DB-level trigger** (not application code, so no
      writer path can forget it) on any change to
      `status`/`flag_confidence`/`final_points_awarded`/`resolved_at`;
      index on `(user_id, updated_at)` created — this is what
      `GET /api/runs?since=` (T2.14c) filters on

---

### T2.3 — Supabase Auth integration (mobile sign up/in + backend JWT verification)

**Objective:** Give users a persistent identity across devices/sessions.

**Scope:**
- Yang dikerjakan: Supabase Auth Swift SDK wired into `ios/` (sign
  up/sign in SwiftUI screens, session persistence via Keychain), JWT
  verification middleware on `backend/` API routes.
- Yang TIDAK dikerjakan: profile completion (region/username — T2.4),
  any custom backend-issued session tokens (auth is Supabase-native per
  tech-spec.md).

**Depends on:** T2.1, T0.2

**Reference:** [tech-spec.md](../tech-spec.md) §1 (Auth row),
[database-api-spec.md](../database-api-spec.md) §2 (Auth section)

**Definition of Done:**
- [ ] User can sign up and sign in from the mobile app
- [ ] Session persists across app restarts (product-spec AC 4.1.3)
- [ ] A protected backend route rejects requests without a valid JWT
      (`401`, per database-api-spec.md §3)

---

### T2.4 — POST /api/profile/complete endpoint

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

**Reference:** [database-api-spec.md](../database-api-spec.md) §2.1

**Definition of Done:**
- [ ] Endpoint creates/updates the `User` row with submitted fields,
      matches request/response shape in database-api-spec.md §2.1
- [ ] Request rejected with `400` if any of the 3 region fields is
      missing or empty
- [ ] Mobile onboarding flow calls this after first sign-in

---

### T2.5 — POST /api/runs endpoint — ingestion only (no calc/anti-cheat yet)

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

**Reference:** [database-api-spec.md](../database-api-spec.md) §2.2, §3

**Definition of Done:**
- [ ] A run payload posted from a REST client creates a `Run` row with
      correct fields
- [ ] Endpoint requires valid auth (rejects unauthenticated requests)
- [ ] `409 Conflict` returned for a run submitted by a user with no
      region set
- [ ] `422` returned for a `gps_route` point missing `timestamp` or
      `elevation`
- [ ] `400` returned for zero/negative `distance_meters` or
      `duration_seconds` (database-api-spec.md §3)

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

**Reference:** [tech-spec.md](../tech-spec.md) §2.2, §2.2b

**Definition of Done:**
- [ ] Given identical input, this module and the mobile T1.1 function
      produce identical point output — verified via both sides' unit
      tests passing against `shared/point-formula.fixtures.json`
      (tech-spec.md §2.2b), not via a literal shared import
- [ ] Parity test fails if `shared/point-formula.fixtures.json` is empty
      (row-count assertion) — same requirement as T1.1's, so neither side
      can pass this DoD against a vacuous fixture
- [ ] No formula constants hand-duplicated without also updating
      `shared/point-formula.fixtures.json` (repo-coding-rules.md §4 PR
      checklist)

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

**Reference:** [tech-spec.md](../tech-spec.md) §2.4

**Definition of Done:**
- [ ] Fixture corpus checked into the repo with a documented format
- [ ] Covers every case in tech-spec.md §2.4 (pace cap, GPS speed jump,
      teleport, elevation anomaly, combined) plus clean/normal negative
      controls
- [ ] At least 3 fixtures are genuine recorded routes (not purely
      synthetic)

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

**Reference:** [tech-spec.md](../tech-spec.md) §2.4 (Pace cap row)

**Definition of Done:**
- [ ] Synthetic route with a >1km segment faster than 3:00/km triggers
      exclusion of that segment and the correct flag string
- [ ] Normal-pace routes are unaffected (no false positive on the happy
      path)

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

**Reference:** [tech-spec.md](../tech-spec.md) §2.4 (GPS speed jump row),
§2.4.1 (status determination — single source of truth, owned by T2.12a)

**Definition of Done:**
- [ ] Synthetic route with a sustained >25km/h jump triggers segment
      exclusion and the correct `anomaly_flags` entry
- [ ] Normal routes unaffected
- [ ] This task's DoD does not assert any run `status` outcome — that
      belongs to T2.12a's boundary tests

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

**Reference:** [tech-spec.md](../tech-spec.md) §2.4 (Distance/duration
sanity row), §2.4.1 (status determination — single source of truth,
owned by T2.12a)

**Definition of Done:**
- [ ] Synthetic route with an implausible location jump excludes the
      correct segment and adds the correct `anomaly_flags` entry
- [ ] This task's DoD does not assert any run `status` outcome — that
      belongs to T2.12a's boundary tests

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

**Reference:** [tech-spec.md](../tech-spec.md) §2.4 (Elevation anomaly row)

**Definition of Done:**
- [ ] Synthetic route with an implausible elevation jump adds the correct
      flag alongside (not instead of) other checks
- [ ] Elevation anomaly alone (without another trigger) does not flag a
      run — matches "additional signal, not a trigger tunggal" rule

---

### T2.11 — Trust score model + trust_multiplier

**Objective:** Turn repeated flagging into a graduated consequence instead
of a binary ban, per tech-spec.md's explicit false-positive concern.

**Scope:**
- Yang dikerjakan: `User.trust_score` field usage — decreases on repeated
  flags within a period, `trust_multiplier` applied to `final_points` per
  tech-spec.md §2.2 formula; users below a trust threshold hidden from
  public leaderboard (not banned).
- Yang TIDAK dikerjakan: any manual admin review UI/tooling — that's
  operational tooling, not in this phase's scope.

**Depends on:** T2.7, T2.8, T2.9, T2.10

**Reference:** [tech-spec.md](../tech-spec.md) §2.4 (Trust score row)

**Definition of Done:**
- [ ] Repeated flags within the configured window measurably reduce
      `trust_score`
- [ ] `final_points` calculation applies `trust_multiplier` correctly
- [ ] A user below the trust threshold is excluded from leaderboard
      queries (verified once T2.19 exists — mark this DoD item complete
      only after cross-checking with that endpoint)

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

**Reference:** [tech-spec.md](../tech-spec.md) §2.4.1

**Definition of Done:**
- [ ] Boundary tests at just-below-`FLAG_THRESHOLD_PCT`, within the LOW
      confidence sub-band, within the HIGH confidence sub-band, and
      at/above `REJECT_THRESHOLD_PCT` all resolve to the correct
      aggregate status and `flag_confidence`
- [ ] Status/confidence resolution logic lives only here — T2.7–T2.10 do
      not decide status themselves (fix to Round 2 finding B-5)
- [ ] `FLAG_THRESHOLD_PCT`/`REJECT_THRESHOLD_PCT`/`FLAG_LOW_MAX_PCT` read
      from configuration, not hardcoded

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

**Reference:** [database-api-spec.md](../database-api-spec.md) §2.2,
[tech-spec.md](../tech-spec.md) §2.4.1

**Definition of Done:**
- [ ] Response matches all three example shapes in database-api-spec.md
      §2.2 (validated, flagged, rejected), status code `201`
- [ ] No `PointTransaction` written for immediate `rejected` — verified
      by test, not just asserted in prose
- [ ] Every written `PointTransaction` references a valid `season_id`
      from the season seeded by T2.17
- [ ] `resolved_at` set correctly per status (null only while `flagged`)
- [ ] `User.total_points`/`current_level` correctly reflect the ledger
      after multiple runs

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

**Reference:** [database-api-spec.md](../database-api-spec.md) §3

**Definition of Done:**
- [ ] Duplicate submission (same `user_id`+`started_at`) returns the
      existing result, no duplicate `PointTransaction`
- [ ] Concurrent duplicate submissions (race condition, not just
      sequential retries) still produce exactly one `PointTransaction` —
      enforced by the DB constraint, not application-level locking alone

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

**Reference:** [tech-spec.md](../tech-spec.md) §4

**Definition of Done:**
- [ ] p95 response time < 1.5s at a named synthetic load (e.g. 100
      concurrent submissions)
- [ ] Result documented (load tool used, dataset size, measured p95)

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

**Reference:** [tech-spec.md](../tech-spec.md) §2.4.1

**Definition of Done:**
- [ ] A LOW-confidence `flagged` run with no manual action resolves to
      `approved` after `REVIEW_WINDOW_LOW`
- [ ] A HIGH-confidence `flagged` run with no manual action remains
      `flagged` indefinitely — explicitly tested, not just assumed
- [ ] A `flagged` run (either confidence) manually overridden to
      `rejected` produces a compensating negative `PointTransaction`,
      original transaction untouched, and `Run.final_points_awarded` is
      set to `0` (the net award — database-api-spec.md §1)
- [ ] `resolved_at` **and** `updated_at` are set correctly on both auto-
      and manual resolution; `flag_confidence` is retained (not nulled)
      on both `approved` and override-`rejected` outcomes
- [ ] `REVIEW_WINDOW_LOW` and both threshold constants are configuration,
      not hardcoded

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

**Reference:** [tech-spec.md](../tech-spec.md) §2.4.1,
[architecture.md](../architecture.md) §2 (step 8)

**Definition of Done:**
- [ ] Job registered as a real Vercel Cron route with a schedule in
      `vercel.json` — not just application logic that nothing calls
- [ ] A LOW-confidence `flagged` run left untouched auto-resolves to
      `approved` within `REVIEW_WINDOW_LOW` + one job interval (observed
      end-to-end, not just unit-tested)
- [ ] A HIGH-confidence `flagged` run is never touched by this job, no
      matter how long it remains unresolved

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

**Reference:** [tech-spec.md](../tech-spec.md) §2.4, §2.4.1,
[development-plan.md](../development-plan.md) Fase 2 hard dependency

**Definition of Done:**
- [ ] All four anti-cheat checks demonstrably trigger correctly against
      the T2.6b fixture corpus via automated tests
- [ ] Negative controls (clean runs) produce zero false flags
- [ ] Resolution lifecycle verified: LOW-confidence `flagged` →
      `approved` auto-resolve via the actual Cron job (T2.12f), HIGH-
      confidence `flagged` runs confirmed to NEVER auto-resolve, and
      manual `flagged` → `rejected` override produces a correct
      compensating transaction
- [ ] Test suite is part of the CI pipeline (not a one-off manual run)
- [ ] Sign-off recorded: this task is the explicit gate T2.21 checks for
      before enabling the public leaderboard

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

**Reference:** [tech-spec.md](../tech-spec.md) §3

**Definition of Done:**
- [ ] A run recorded fully offline syncs automatically once connectivity
      returns
- [ ] Local `estimatedPoints` is replaced by server `final_points_awarded`
      (stored locally as `finalPointsAwarded`) in the UI after sync
- [ ] Repeated sync failures do not drop the run — it remains queued and
      retried, never silently discarded
- [ ] After a successful sync, the local row's `serverRunId`,
      `serverStatus`, `flagConfidence`, `anomalyFlags`, and `resolvedAt`
      (T0.6 attributes) are populated from the `201` response — verified
      specifically for a **`flagged`** response, since
      `serverStatus = "flagged"` is the entire trigger condition T2.14d
      watches for and `serverRunId` is the only correlation key it has

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

**Reference:** [product-spec.md](../product-spec.md) AC 4.3.2,
[tech-spec.md](../tech-spec.md) §2.4.1, §3 step 5,
[database-api-spec.md](../database-api-spec.md) §2.2

**Definition of Done:**
- [ ] Run summary/history entry displays status-appropriate,
      human-readable copy for `flagged` (low and high, differentiated),
      `approved`, and `rejected` — never just the raw status string
- [ ] Raw `anomalyFlags` codes are never shown to the user directly —
      always translated via the lookup table
- [ ] Reopening the app / next sync after a background resolution
      (`flagged`→`approved` or `flagged`→`rejected`) reflects the
      updated status and copy — powered by T2.14d's reconciliation loop,
      not by any mechanism internal to this task

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

**Reference:** [database-api-spec.md](../database-api-spec.md) §2.2b, §3,
[tech-spec.md](../tech-spec.md) §4 (reconciliation NFR row)

**Definition of Done:**
- [ ] Deployed; `400` only for a present-but-unparseable `since`, never
      for a missing one (server defaults the lookback instead)
- [ ] Response includes `server_time` and `has_more`, capped at 200 rows
      ordered `updated_at` ASC
- [ ] With >200 qualifying rows: response contains the 200
      oldest-changed rows and `has_more: true`; a follow-up call using
      the last row's `updated_at` as `since` returns the next batch, and
      repeating eventually reaches `has_more: false` with no row ever
      skipped — verified by test, not just asserted in prose
- [ ] A run whose `updated_at` changed but whose `resolved_at` is still
      `null` (i.e. a run that just transitioned *into* `flagged`) **is**
      returned by `?since=` — verified by test, so a
      `resolved_at`-based filter implementation cannot pass this item
- [ ] Response matches both example shapes in database-api-spec.md
      §2.2b, including the `flagged → rejected` override entry with
      `flag_confidence` retained (not null) and `final_points_awarded: 0`
- [ ] Requests return only the authenticated caller's own runs — verified
      with a second user's token (no cross-user leakage)
- [ ] `Run.updated_at` index in place; p95 < 300ms per tech-spec.md §4

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

**Reference:** [tech-spec.md](../tech-spec.md) §3 step 7,
[architecture.md](../architecture.md) §2 step 10,
[database-api-spec.md](../database-api-spec.md) §2.2b

**Definition of Done:**
- [ ] Client skips the call entirely when it holds zero locally-`flagged`
      runs
- [ ] Calls respect the ≥15-minute-since-last-attempt floor, including
      across an app restart (verified against the persisted attempt
      timestamp, not just in-memory state)
- [ ] First-ever call omits `since`; every subsequent call sends the
      previously-persisted server-issued cursor (`server_time` when the
      prior response had `has_more: false`, the prior response's last row
      `updated_at` when `has_more: true` — never a device timestamp) — a
      deliberately-skewed device clock does not cause a resolution to be
      missed (tested explicitly)
- [ ] A `has_more: true` response is fully drained via immediate
      follow-up calls before the loop waits for the next cycle
- [ ] A batch of ≥200 rows sharing one identical `updated_at` terminates
      the drain loop (no row newer than the cursor on the follow-up call)
      instead of re-calling forever — tested explicitly, not just asserted
      in prose
- [ ] A run that resolves from `flagged` to `approved` or `rejected` in
      the background (via T2.12f's cron for LOW, or a manual override
      for either confidence) is reflected in the matching local row
      **and** triggers a call to `ProgressViewModel.refresh()` (T2.16),
      within one reconciliation cycle (verified end-to-end — a Core Data
      save alone is not sufficient to pass this item)
- [ ] An unmatched `run_id` in a response (no local row) is ignored, not
      inserted as a new row
- [ ] A failed reconciliation call updates the attempt timestamp but not
      `last_reconciled_at`, and does not affect T2.14's upload-retry
      queue

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

**Reference:** [database-api-spec.md](../database-api-spec.md) §2.3, §1
(Level note)

**Definition of Done:**
- [ ] Response shape matches database-api-spec.md §2.3 example
- [ ] Values match what's derivable from the `PointTransaction` ledger for
      that user
- [ ] Backend `levelThresholds` values match database-api-spec.md §1's
      table exactly, row for row — verified by a test (same as T1.3's
      requirement on the Swift side)

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

**Reference:** [architecture.md](../architecture.md) §3 (State layer)

**Definition of Done:**
- [ ] Screen shows server-derived values when online/synced
- [ ] Screen gracefully falls back to local estimate when offline (no
      broken UI state)
- [ ] `ProgressViewModel.refresh()` is callable from outside the screen
      (e.g. T2.14d) and re-fetches `GET /api/users/me/progress` — verified
      directly, not only via the screen's own initial load

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

**Reference:** [database-api-spec.md](../database-api-spec.md) §2.5

**Definition of Done:**
- [ ] Endpoint returns the seeded active season matching the response
      shape in database-api-spec.md §2.5
- [ ] `PointTransaction` writes from T2.12c correctly reference this
      season's `season_id`

---

### T2.18 — LeaderboardEntry precompute job (global scope)

**Objective:** Build the precompute mechanism architecture.md §4
prescribes — leaderboard reads must never aggregate live.

**Scope:**
- Yang dikerjakan: Vercel Cron job reading `PointTransaction` (scoped to
  active season) **from runs with `RUN.status` `validated` or `approved`
  only** (tech-spec.md §2.4.1 — `flagged`/`rejected` excluded), writing
  `LeaderboardEntry` rows for `scope_type=global` only, indexed per
  architecture.md §4. Also writes/updates the single `LEADERBOARD_SCOPE`
  row for `scope_type=global` (`scope_id='GLOBAL'` sentinel — NOT NULL,
  `insufficient_data=false` hardcoded, `user_count`, `computed_at`) —
  `global` is an explicit scope value in that table from this task
  onward, not an absent row (database-api-spec.md §1).
- Yang TIDAK dikerjakan: per-region scopes (kecamatan/kabupaten_kota/
  provinsi) — that's T3.2 in Fase 3, explicitly deferred.

**Depends on:** T2.12b, T2.17

**Reference:** [architecture.md](../architecture.md) §4,
[database-api-spec.md](../database-api-spec.md) §1

**Definition of Done:**
- [ ] Job runs on a ≤15-minute interval and correctly ranks all users by
      total points in the active season
- [ ] `LeaderboardEntry` table indexed on `(season_id, scope_type,
      scope_id, points DESC)` per architecture.md §4
- [ ] A `LEADERBOARD_SCOPE` row for `scope_type=global` exists after the
      first run of this job, with `insufficient_data=false`
- [ ] A `flagged` run's points do not appear in `LeaderboardEntry`; the
      same run's points **do** appear after it resolves to `approved`,
      on the job's next run; a `rejected` run's points never appear —
      verified by test (development-plan.md Fase 2 DoD, the fairness
      guarantee tech-spec.md §2.4.1 exists to protect)
- [ ] Job execution time stays well within the 15-minute window at test
      data volume

---

### T2.19 — GET /api/leaderboard endpoint (global scope)

**Objective:** Expose the precomputed global leaderboard to clients.

**Scope:**
- Yang dikerjakan: endpoint per database-api-spec.md §2.4, `scope=global`
  only for this task (region filters come in T3.4).
- Yang TIDAK dikerjakan: region-scoped queries.

**Depends on:** T2.18

**Reference:** [database-api-spec.md](../database-api-spec.md) §2.4

**Definition of Done:**
- [ ] Response matches database-api-spec.md §2.4 example shape
      (`entries`, `me`, `computed_at`)
- [ ] p95 response time < 300ms per tech-spec.md §4 (reading from
      precomputed table, not live aggregation)
- [ ] Users below the trust threshold (T2.11) do not appear in results

---

### T2.20 — Global leaderboard screen on mobile

**Objective:** Ship the user-facing feature this phase has been building
toward.

**Scope:**
- Yang dikerjakan: screen consuming `GET /api/leaderboard?scope=global`,
  showing top N + the current user's own rank even if outside top N
  (product-spec AC 4.5.1).
- Yang TIDAK dikerjakan: region filter UI (Fase 3).

**Depends on:** T2.19

**Reference:** [product-spec.md](../product-spec.md) §4.5

**Definition of Done:**
- [ ] Top N entries and the user's own position both render correctly
- [ ] Data staleness shown or at least consistent with the ≤15-minute
      precompute freshness target

---

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

**Depends on:** T2.13, T2.20, T2.14, T2.16, T2.14b

**Reference:** [development-plan.md](../development-plan.md) Fase 2 hard
dependency ("anti-cheat must ship and be verified before the global
leaderboard is made visible")

**Definition of Done:**
- [ ] T2.13's test suite is green in the production/release environment,
      not just locally
- [ ] Leaderboard feature flag (if used) confirmed enabled only after the
      above
- [ ] Offline sync (T2.14) and server-backed progress screen (T2.16) are
      both verified working, not just the leaderboard — Fase 2's DoD
      leads with "offline run syncs correctly," not just the leaderboard
      being visible
- [ ] The "visible reason" clause of Fase 2's DoD is verified, not just
      the initial-sync half: a `flagged` run shows its reason (T2.14b),
      **and** a background resolution (LOW auto-approve or manual
      override) is reflected in the app after reconciliation
      (T2.14b/T2.14d) — Phase 2 cannot be signed off with this branch
      unbuilt, even though it doesn't touch the leaderboard itself
- [ ] Sign-off recorded before considering Phase 2 complete
