# Phase 3 — Local Leaderboard Granular + Season System

Source: [development-plan.md](../development-plan.md) Fase 3

Dependency note from development-plan.md: this phase depends on Fase 2's
anti-cheat and precompute infrastructure already being solid — local
leaderboards multiply the number of scopes being computed, so any gap
carried over from Fase 2 gets amplified here.

---

### T3.1 — Mobile onboarding UX blocking run-start until region is set

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

**Depends on:** T2.4

**Reference:** [product-spec.md](../product-spec.md) AC 4.1.2,
[database-api-spec.md](../database-api-spec.md) §3

**Definition of Done:**
- [ ] Mobile app blocks the run-start flow (or blocks sync) until all 3
      region fields are set, before any network call is made
- [ ] Confirmed (not re-implemented) that the backend still returns `409`
      per T2.5/database-api-spec.md §3 as a defense-in-depth fallback

---

### T3.2 — Extend precompute job to per-scope aggregation (kecamatan/kabupaten_kota/provinsi)

**Objective:** Scale the Fase 2 global-only precompute job to the
granular regional scopes the local leaderboard needs.

**Scope:**
- Yang dikerjakan: extend T2.18's job to also produce `LeaderboardEntry`
  rows per `scope_type` (`kecamatan`, `kabupaten_kota`, `provinsi`) using
  each user's region fields; also writes the `user_count`/`computed_at`
  row into `LEADERBOARD_SCOPE` (database-api-spec.md §1, table already
  migrated in Fase 2 via T2.2 — this task adds local-scope rows to it,
  it does not create the table) for each local scope computed, as the
  storage T3.3's `insufficient_data` flag needs.
- Yang TIDAK dikerjakan: setting the `insufficient_data` boolean itself
  (T3.3) — this task only produces the raw per-scope rankings and counts;
  the global scope's `LEADERBOARD_SCOPE` row (already written by T2.18
  since Fase 2).

**Depends on:** T2.18

**Reference:** [architecture.md](../architecture.md) §4

**Definition of Done:**
- [ ] Job produces correct `LeaderboardEntry` rows for all three regional
      scope types, in addition to global
- [ ] Job execution time still stays within the 15-minute window at
      expected data volume (multiple scopes per user increases row count)

---

### T3.3 — Insufficient_data handling in precompute job

**Objective:** Prevent a near-empty regional leaderboard from looking
broken to early users in low-density areas.

**Scope:**
- Yang dikerjakan: per architecture.md §4 — scopes with fewer than a
  configurable threshold (e.g. 5 users) get `insufficient_data = true`
  written to their `LEADERBOARD_SCOPE` row (T3.2) instead of emitting a
  sparse ranking.
- Yang TIDAK dikerjakan: the client-side message itself (T3.5 handles
  rendering).

**Depends on:** T3.2

**Reference:** [architecture.md](../architecture.md) §4

**Definition of Done:**
- [ ] A scope below the threshold is flagged `insufficient_data` in the
      precompute output
- [ ] Threshold is a configurable value, not hardcoded inline

---

### T3.4 — Extend GET /api/leaderboard with scope filters

**Objective:** Expose the regional data from T3.2/T3.3 to clients.

**Scope:**
- Yang dikerjakan: extend T2.19's endpoint to accept
  `scope=kecamatan|kabupaten_kota|provinsi` + `scope_id`, return
  `insufficient_data` flag (read from `LEADERBOARD_SCOPE`) per
  database-api-spec.md §2.4.
- Yang TIDAK dikerjakan: global scope behavior (unchanged from T2.19).

**Depends on:** T3.2, T3.3, T2.19

**Reference:** [database-api-spec.md](../database-api-spec.md) §2.4

**Definition of Done:**
- [ ] Endpoint correctly filters by all three regional scope types
- [ ] `insufficient_data: true` returned with `entries: []` for
      under-threshold scopes, never a `404` (per database-api-spec.md §3)

---

### T3.5 — Local leaderboard screen with scope filter UI

**Objective:** Ship the user-facing local leaderboard feature.

**Scope:**
- Yang dikerjakan: extend/reuse T2.20's screen with a scope switcher
  (kecamatan/kabupaten_kota/provinsi), "belum cukup data" message when
  `insufficient_data` is true (product-spec AC 4.6.2).
- Yang TIDAK dikerjakan: letting users pick an arbitrary region to view
  (AC 4.6.3 — region is always the user's own profile region, not a free
  browse).

**Depends on:** T3.4, T2.20

**Reference:** [product-spec.md](../product-spec.md) §4.6

**Definition of Done:**
- [ ] User can switch between kecamatan/kabupaten_kota/provinsi views of
      their own region
- [ ] Insufficient-data scopes show the dedicated message, not an empty
      list

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

**Reference:** [database-api-spec.md](../database-api-spec.md) §1 (Season entity)

**Definition of Done:**
- [ ] A season can be transitioned through all three states correctly
- [ ] Invariant enforced: never more than one `active` season
      simultaneously

---

### T3.7 — Season-scoped rank reset on transition

**Objective:** Implement the core season mechanic — competition resets,
lifetime progress doesn't.

**Scope:**
- Yang dikerjakan: on new season activation, `LeaderboardEntry` precompute
  (T3.2) begins scoping fresh to the new `season_id`; explicit
  confirmation that `User.total_points`/`current_level` are untouched by
  the transition (product-spec AC 4.7.1).
- Yang TIDAK dikerjakan: historical rank retention (T3.8 — separate
  concern).

**Depends on:** T3.6, T3.2

**Reference:** [product-spec.md](../product-spec.md) AC 4.7.1

**Definition of Done:**
- [ ] After a season transition, leaderboard rank starts fresh (verified:
      a top-ranked user in the old season is not automatically top-ranked
      in the new one just from carried-over lifetime points)
- [ ] `User.total_points`/`current_level` unchanged across the transition

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

**Depends on:** T3.7

**Reference:** [product-spec.md](../product-spec.md) AC 4.7.3

**Definition of Done:**
- [ ] A user's final rank from a completed season remains queryable after
      the season ends
- [ ] Data is not overwritten or lost when a new season's precompute job
      runs

---

### T3.9 — Season info screen with countdown

**Objective:** Surface season timing to users (product-spec AC 4.7.2).

**Scope:**
- Yang dikerjakan: screen consuming `GET /api/seasons/active`, showing
  season name and `days_remaining` countdown.
- Yang TIDAK dikerjakan: past-season browsing (that's T3.8's concern).

**Depends on:** T3.6, T2.17

**Reference:** [database-api-spec.md](../database-api-spec.md) §2.5

**Definition of Done:**
- [ ] Countdown displays correctly and updates as time passes (not just
      on app open)
- [ ] Screen reflects the currently active season correctly across a
      transition (T3.6)

---

### T3.10 — End-to-end verification: season close/open cycle (phase DoD gate)

**Objective:** Verify the actual acceptance bar from development-plan.md
Fase 3 before considering this phase done.

**Scope:**
- Yang dikerjakan: simulate closing an active season and opening a new
  one in a test environment; confirm lifetime stats intact, all three
  regional leaderboard scopes recompute correctly for the new season,
  historical final rank remains viewable.
- Yang TIDAK dikerjakan: any new functionality — verification only, bugs
  found route back to T3.1–T3.9.

**Depends on:** T3.1, T3.5, T3.7, T3.8

**Reference:** [development-plan.md](../development-plan.md) Fase 3 DoD

**Definition of Done:**
- [ ] Full season close→open cycle tested with seeded multi-user data
      across all three regional scopes
- [ ] Lifetime `User.total_points`/`current_level` verified unchanged
      post-transition
- [ ] Previous season's final rank still retrievable after transition
- [ ] Sign-off recorded before considering Phase 3 complete
