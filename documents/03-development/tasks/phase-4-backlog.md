# Phase 4 — Backlog (not scheduled)

Source: [development-plan.md](../development-plan.md) Fase 4

This phase is explicitly **out of scope for execution now**. Listed at
high level only, so these items are known and deliberately deferred, not
forgotten. Do not break these down into granular tasks until the phase is
actually scheduled — doing so now would be speculative work against
requirements that haven't been validated yet (product-spec.md §5
Non-goals explains why each is deferred).

**One exception to "high level only":** the Local Leaderboard tasks
**T3.2–T3.5**, moved here from Fase 3 on 2026-09-21, are kept in full detail
(Objective / Scope / Depends on / DoD) in the section at the bottom, because
they were already specified and audited before the product decision to defer
them — see "Deferred from MVP v1 — Local Leaderboard". They are still
**not scheduled**.

- **T3.2–T3.5 — Local Leaderboard** (region-scope precompute,
  `insufficient_data`, `GET /api/leaderboard` scope filters, screen).
  Deferred to v1.1; detail at the bottom of this file.

- **T4.1 — Circle / Clan / Club** (data model + UI). Depends on the `club_id`
  field already reserved on `User` (database-api-spec.md §1) and the
  sketched `Club` entity never migrated in Fase 2.
- **T4.2 — Club War.** Depends on T4.1.
- **T4.3 — Matchmaking between circles.** Depends on T4.1.
- **T4.4 — Monetization: seasonal pass.**
- **T4.5 — Monetization: advanced statistics.**
- **T4.6 — Monetization: exclusive badge.**
- **T4.7 — Monetization: premium profile.**
- **T4.8 — B2B dashboard: running club.**
- **T4.9 — B2B dashboard: event organizer.**
- ~~**T4.10 — Route map visualization** (Mapbox integration, per
  tech-spec.md §1 Maps SDK row).~~ **Moved to Fase 1, 2026-09-12** — split
  into live map + static map (product-spec.md §4.8-4.9,
  tasks/phase-1-core-loop-offline.md T1.8-T1.9), using MapKit (native, no
  cost) instead of Mapbox. No longer backlog; task number retired, not
  reused.
- **T4.11 — Android support** — postponed indefinitely, no timeline
  (platform decision, not tech-debt — tech-spec.md §1). Would require its
  own tracking mechanism decision (Android has no `CLLocationManager`
  equivalent) and its own local persistence choice, not a direct port of
  the iOS implementation.
- **T4.12 — Redis-backed real-time global leaderboard cache** — Open
  Question in architecture.md §4, only relevant if precompute freshness
  (≤15 min) proves insufficient at scale.
- **T4.13 — Native iOS platform integrations** (Live Activities, Dynamic
  Island, HealthKit, WidgetKit) — capabilities newly available now the app
  is Swift-native, explicitly not v1 scope (tech-spec.md §1,
  development-plan.md Fase 4, mvp-report.md §8). Pivot introduced
  capability, not a feature request — do not start until Fase 1–3 have
  shipped.
- **T4.14 — Apple Watch companion app.** Added 2026-09-12. Low priority,
  large effort — separate target, WatchConnectivity, its own tracking/UI
  considerations. No dependency on anything else in this backlog.
- **T4.15 — Social Feed** (post run achievements, view others' posts).
  Added 2026-09-12 — previously existed only as an unreconciled draft in
  user-flow.md (§2.7 "Social Feed / Posting"), never represented in
  product-spec.md/development-plan.md/tasks/* until now. Now formally
  tracked here (see product-spec.md §5 Non-goals) instead of remaining an
  orphaned draft. **Recommendation, not the locked call:** Fase 4, same
  phase as Circle (T4.1) — not Fase 3. Reasoning: product-spec.md §1's
  core bet is that the progression loop must be proven rewarding for a
  single player with zero social features before any social layer is
  added (the same reasoning that keeps Circle at Fase 4); Social Feed is
  a social/engagement feature exactly like Circle, arguably with *more*
  unvalidated surface than Circle (audience/privacy controls, moderation,
  its coupling to the Premium tier system in user-flow.md which is itself
  unvalidated) — promoting it to Fase 3 would be a bigger, unreviewed
  scope decision than this pass is meant to make. If there's a reason to
  prioritize it above Circle specifically, that's a product call worth
  revisiting explicitly, not something to default into via this cleanup.
- **T4.16 — Comment on social feed posts.** Depends on T4.15 (Social Feed
  itself) existing first — cannot be scheduled independently of it.

---

## Deferred from MVP v1 — Local Leaderboard (T3.2–T3.5)

> **Moved here from Fase 3 on 2026-09-21. Deferred to v1.1 — NOT cancelled.**
> Product decision: the local leaderboard is cut from MVP v1 (v1 = Global
> Leaderboard only). It needs high user density to be useful — with few
> early users a kecamatan holds a handful of people and the board is
> empty/uncompetitive, while a Global board already feels "local" at small
> scale. The value appears *after* there are many users; it is not a launch
> prerequisite.
>
> **Why these four are written out in full** even though the rest of this
> file is high-level only: they were already specified and audited across
> several rounds (region hierarchy kecamatan → kabupaten/kota → provinsi,
> soft-delete exclusion, `insufficient_data`), and that work should not be
> redone. The text below is moved **verbatim** — Objective / Scope / Depends
> on / DoD unchanged. IDs T3.2–T3.5 are kept (not renumbered) so every
> existing cross-reference still resolves.
>
> **Already prepared in v1, do not redo:** region fields on `User`
> (collected at onboarding, T2.4/T3.1), the `LEADERBOARD_SCOPE` table and
> the `scope_type` values (database-api-spec.md §1, migrated in T2.2), and
> the `scope`/`scope_id` request shape in database-api-spec.md §2.4 (only
> `global` is served in v1; region scopes answer `400` per T2.19).
>
> **Spec:** product-spec.md §4.6 (AC 4.6.1–4.6.3, preserved, not
> Must-have v1). **Trigger to schedule:** enough active users per region
> for a regional board to be non-empty. **Dependencies that remain valid:**
> T2.18 (global precompute) and T2.19/T2.20 (endpoint and screen) — all
> built in Fase 2.

### T3.2 — Extend precompute job to per-scope aggregation (kecamatan/kabupaten_kota/provinsi)

**Objective:** Scale the Fase 2 global-only precompute job to the
granular regional scopes the local leaderboard needs.

**Scope:**
- Yang dikerjakan: extend T2.18's job to also produce `LeaderboardEntry`
  rows per `scope_type` (`kecamatan`, `kabupaten_kota`, `provinsi`) using
  each user's region fields — **inherits T2.18's `deleted_at IS NULL`
  exclusion and rebuild-not-upsert model** (database-api-spec.md §2.1b,
  added 2026-09-13 Round 7 finding B7-12/B7-P4), not a separate filter to
  reimplement; also writes the `user_count`/`computed_at` row into
  `LEADERBOARD_SCOPE` (database-api-spec.md §1, table already migrated in
  Fase 2 via T2.2 — this task adds local-scope rows to it, it does not
  create the table) for each local scope computed, as the storage T3.3's
  `insufficient_data` flag needs.
- Yang TIDAK dikerjakan: setting the `insufficient_data` boolean itself
  (T3.3) — this task only produces the raw per-scope rankings and counts;
  the global scope's `LEADERBOARD_SCOPE` row (already written by T2.18
  since Fase 2).

**Depends on:** T2.18

**Reference:** [architecture.md](../../02-architecture/architecture.md) §4

**Definition of Done:**
- [ ] Job produces correct `LeaderboardEntry` rows for all three regional
      scope types, in addition to global
- [ ] A soft-deleted user (`User.deleted_at` non-null) never appears in
      any regional-scope `LeaderboardEntry` row after the first job run
      following their deletion (T2.22)
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

**Reference:** [architecture.md](../../02-architecture/architecture.md) §4

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

**Reference:** [database-api-spec.md](../../02-architecture/database-api-spec.md) §2.4

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

**Reference:** [product-spec.md](../../01-product/product-spec.md) §4.6

**Definition of Done:**
- [ ] User can switch between kecamatan/kabupaten_kota/provinsi views of
      their own region
- [ ] Insufficient-data scopes show the dedicated message, not an empty
      list

---
