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
them — see "Deferred from MVP v1 — Local Leaderboard". **Update 2026-09-22:
CANCELLED PERMANENTLY, not deferred** (PM sign-off — scope too broad for the
leaderboard logic needed). Kept in full detail below as a historical record
only, per this repo's convention for reversed decisions — will not be
implemented.

- ~~**T3.2–T3.5 — Local Leaderboard** (region-scope precompute,
  `insufficient_data`, `GET /api/leaderboard` scope filters, screen).~~
  **CANCELLED PERMANENTLY 2026-09-22**, not deferred to v1.1 — see product-spec.md
  §4.6. Detail kept at the bottom of this file for historical record only.

- **T4.1 — ~~Circle / Clan~~ Club** (data model + UI). **Renamed 2026-09-23**
  (PM decision) — already matched the `club_id` field reserved on `User`
  (database-api-spec.md §1) and the sketched `Club` entity never migrated
  in Fase 2, so this brings the name into alignment with existing code.
- **T4.2 — Club War.** Depends on T4.1. **CONFIRMED TO BUILD 2026-09-23**
  (was "nice to have v2+") — see product-spec.md §4.19 for the base decision
  (max 3 clubs/war, self-serve by Premium Club owner/admin, ADR-0014's
  event-scale rule). ~~vs. genuinely open (mechanics, win condition,
  duration).~~ **Mechanism finalized 2026-09-23** (§4.19 AC1-AC9): Participation
  Rate win condition (reused from §4.20 Club Aktif), fixed 48-hour duration,
  targeted challenge/invite start (not matchmaking — stays separate from
  T4.3 below), tie-break + forfeit rules, no anti-farming limit in v1.
  **AC7 resolved 2026-09-23**: a declined/timed-out challenge dissolves
  with zero Club War Record entry for anyone — not a forfeit, the war
  never started. Fully unblocked for schema scoping now. Sub-task
  breakdown: T4.2a (data model), T4.2b (backend API), T4.2c (iOS UI) —
  see their own entries below.
- **T4.2a — Club War: data model.** Depends on T4.2 (mechanism decided),
  T4.1 (Club must exist — currently neither does; `user.club_id` is only
  a reserved nullable column with no FK, `database-api-spec.md` §1 /
  `20260917162813_create_core_schema.sql`). **Scope**: `club` table (does
  not exist yet at all), a membership/roster table (`user.club_id` alone
  may not be enough if owner/admin/member roles need to be distinguished
  — not decided here, this task's own scoping question), and a `club_war`
  table (pending/accepted/declined/active/ended state, per-club score,
  win/loss outcome) — including deciding whether `user.club_id` gets
  promoted to a real FK against the new `club` table or membership stays
  fully separate. **Per §4.19 AC7 (resolved 2026-09-23)**: a `club_war`
  row that dissolves in the pending phase (declined or 24h timeout) must
  NOT feed the Club War Record aggregation — schema needs to distinguish
  "dissolved, never fought" from "ended, real win/loss outcome," not
  just track a single win/loss field that both states would populate.
  **Reference**: product-spec.md §4.19 AC1-AC9, §4.20
  Section 2 (Club War Record's own data needs).
- **T4.2b — Club War: backend API.** Depends on T4.2a. **Scope**: create
  a challenge (target 1-2 specific clubs), accept/decline per invited
  club, **challenge dissolution on decline or 24h timeout (AC7 — no
  Club War Record write, distinct from and not a "forfeit")**, a
  precompute job scoring Participation Rate per war-entered member over
  the 48-hour window once a war is actually active (reusing §4.20
  Section 1's metric, not reimplementing it), the tie-break and
  total-inactivity forfeit rules (AC5-AC6 — active-war-only, do write
  the Club War Record), and an endpoint to read the Record. **Reference**:
  product-spec.md §4.19 AC2-AC9, ADR-0013 (precompute-not-live-derive
  pattern), §4.20 Section 1.
- **T4.2c — Club War: iOS UI.** Depends on T4.2b. **Scope**: send a
  challenge (Premium Club owner/admin only), accept/decline an incoming
  challenge, view an active war's status/score, view the Club War Record
  (shares a screen with §4.20's Club Global Leaderboard, not a separate
  screen — no `screen-inventory.md` entry added by this task itself).
  **Reference**: product-spec.md §4.19 AC1-AC9, §4.20.
- **T4.3 — Matchmaking between clubs.** Depends on T4.1. Still Non-goal,
  no decided shape.
- **T4.4 — Monetization: seasonal pass.**
- **T4.5 — Monetization: advanced statistics.**
- **T4.6 — Monetization: exclusive badge.**
- **T4.7 — Monetization: premium profile.** Premium pricing decided
  2026-09-23 ($7.99/mo + App Store Connect regional tiers, product-spec.md
  §5) — applies to whichever of T4.4–T4.7 eventually ship, not scoped to
  one of them specifically.
- **T4.8 — B2B dashboard: running club.** Unchanged — still a self-serve
  tool, unlike T4.9 below.
- **T4.9 — ~~B2B dashboard: event organizer~~ ~~EO managed service~~ Laju Branded Events.**
  **Concept replaced 2026-09-23 — second reframe, kept at T4.9 (same feature slot, not renumbered),
  same reasoning as product-spec.md §4.21 keeping its own section number.** The prior "EO managed
  service" reframe (2026-09-23, struck through) correctly established Laju-exclusive ownership
  (ADR-0014) but never answered what an "event" technically *is*, which blocked real scoping. That's
  resolved now: see **product-spec.md §4.21** for the full definition — two types (Sponsored /
  Announcement-only), sponsored redirects to an external sponsor site (no registration/reward
  handling in Laju's system), winner determination is a manual Laju-staff process (no automated
  payout), available to all users with no region filter, UI is a card feed in Social tab → Events
  sub-tab. Revenue model changed again along with it: **sponsorship fee** (brand pays for exposure,
  not a per-event service fee — lean-canvas.md §6).
  ~~**Reframed 2026-09-23 (ADR-0014)** — EO gets no dashboard access at all;
  Laju's own team creates/manages events on an EO client's behalf. Revenue
  model changed from tool-subscription to per-event service fee (pricing
  not decided, lean-canvas.md §6). Task name may need to change along with
  it — "dashboard" no longer describes what ships. Real scoping done
  2026-09-23 — see product-spec.md §4.21: recommended minimal shape is
  an admin CLI script (same family as `backend/scripts/season.ts`), no
  dashboard UI at all, since there is zero self-serve surface to build
  one for. Still not a real task (no DoD written) — blocked on one
  genuinely open question that determines the entire shape of the work:
  what an "event" technically *is* (a time-boxed leaderboard scope? a
  data export? something else?). Cannot be scoped into concrete DoD
  items until that's answered.~~
  **Still not a real task (no DoD written) even now** — the "what is an event" blocker is resolved
  (product-spec.md §4.21 has AC1–AC5 and a rough data model), but this backlog file's own top-of-file
  rule says not to break Fase-4 items into granular tasks until the phase is scheduled. Recommended
  creation mechanism carries over unchanged: an admin CLI script (same family as
  `backend/scripts/season.ts`), no dashboard UI, since only Laju staff ever create an Event.
- **T4.17 — Club Global Leaderboard.** Depends on T4.1 (Club must exist)
  and, for its Section 2, T4.2 (Club War must exist — Section 2 has
  nothing to rank without match data). **CONFIRMED TO BUILD 2026-09-23**
  — see product-spec.md §4.20 for the two-section spec (Club Aktif /
  Club War Record). Both sections' 60-day reset cadence is **resolved by
  T4.18 below: applies starting Season 2, not from now** — Season 1
  (currently live, 91 days) has no 60-day cadence to align to yet, so
  this task's own scoping must decide what either section does during
  Season 1 specifically (T4.18 doesn't answer that, only the User
  Season's own length).
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
- **T4.12 — Redis-backed real-time global leaderboard cache** — ~~Open
  Question in architecture.md §4, only relevant if precompute freshness
  (≤15 min) proves insufficient at scale.~~ **CONFIRMED TO BUILD 2026-09-23**
  (PM decision, architecture.md §4's Open Question resolved by product
  decision, not measured data — see lean-canvas.md §7 for the added
  operational cost). Redis sorted set as a read-through cache in front of
  Postgres, global scope only, Postgres stays source of truth.
- **T4.13 — Native iOS platform integrations** (Live Activities, Dynamic
  Island, HealthKit, WidgetKit) — capabilities newly available now the app
  is Swift-native, explicitly not v1 scope (tech-spec.md §1,
  development-plan.md Fase 4, mvp-report.md §8). Pivot introduced
  capability, not a feature request — do not start until Fase 1–3 have
  shipped. **Priority order set 2026-09-23** (PM decision, was unordered):
  1) **Live Activities**, 2) **Dynamic Island**, 3) **WidgetKit**, 4)
  **HealthKit** — Live Activities/Dynamic Island reinforce the core
  run-tracking loop directly (the thing users are already doing while
  running); WidgetKit targets the D7/D30 retention metric (lean-canvas.md
  §8) by giving the app a presence outside the app itself; HealthKit is
  competitive parity (every other running app has it) rather than a Laju
  differentiator, so it's lowest priority. Still one task — this orders
  the work inside it, doesn't split it into four tasks.
- **T4.14 — Companion smartwatch app.** Added 2026-09-12 as "Apple Watch
  companion app," low priority. **Scope expanded and reprioritized
  2026-09-23** (PM decision): confirmed to build, three platforms, strict
  order:
  1) **Apple Watch** (WatchOS/Swift) — fits the existing native stack
     directly (ADR-0001), same language, same team can build it.
  2) **Garmin** (Connect IQ SDK, Monkey C) — entirely separate tech stack
     and toolchain from the rest of this codebase. **Not bundled into this
     task as scoped** — needs its own future scoping pass once Apple Watch
     ships, flagged here rather than estimated blind.
  3) **Huawei Watch** (HarmonyOS or Wear OS, depending on model) — same
     caveat as Garmin: separate stack, needs its own scoping, not bundled
     here.
  No dependency on anything else in this backlog. The Apple Watch phase
  alone is roughly what the original "Apple Watch companion app" scope
  described (separate target, WatchConnectivity, its own tracking/UI
  considerations) — Garmin/Huawei are net-new scope on top of that,
  not refinements of it. **Apple Watch phase real-scoped 2026-09-23** —
  see product-spec.md §4.22: recommended shape is the watch mirroring an
  in-progress phone-tracked run (`WatchConnectivity` relay), not
  independent GPS tracking on the watch — standalone tracking would mean
  a second implementation of the anti-drift/anti-cheat pipeline (ADR-0004,
  ADR-0008) on a new platform, a much larger scope than a "companion."
  **Still not a real task (no DoD written)** — blocked on whether
  phone-free tracking is wanted at all (even as a later phase); that
  answer changes the size of the work by an order of magnitude, same
  category of blocker as T4.9/§4.21's "what is an event."
- **T4.15 — Social Feed** (post run achievements, view others' posts).
  Added 2026-09-12 — previously existed only as an unreconciled draft in
  user-flow.md (§2.7 "Social Feed / Posting"), never represented in
  product-spec.md/development-plan.md/tasks/* until now. Now formally
  tracked here (see product-spec.md §5 Non-goals) instead of remaining an
  orphaned draft. **Recommendation, not the locked call:** Fase 4, same
  phase as Club (T4.1) — not Fase 3. Reasoning: product-spec.md §1's
  core bet is that the progression loop must be proven rewarding for a
  single player with zero social features before any social layer is
  added (the same reasoning that keeps Club at Fase 4); Social Feed is
  a social/engagement feature exactly like Club, arguably with *more*
  unvalidated surface than Club (audience/privacy controls, moderation,
  its coupling to the Premium tier system in user-flow.md which is itself
  unvalidated) — promoting it to Fase 3 would be a bigger, unreviewed
  scope decision than this pass is meant to make. If there's a reason to
  prioritize it above Club specifically, that's a product call worth
  revisiting explicitly, not something to default into via this cleanup.
- **T4.16 — Comment on social feed posts.** Depends on T4.15 (Social Feed
  itself) existing first — cannot be scheduled independently of it.
- **T4.18 — Change User Season length from 91 to 60 days, forward-only.**
  Added 2026-09-23 (PM decision — see product-spec.md §4.20). **DECIDED
  2026-09-23, NOT YET IMPLEMENTED:**
  - **Season 1 — 2026 (currently live, 2026-09-01→2026-11-30, 91 days):
    finishes on its original schedule, unmodified. Not cut short.**
  - **Season 2 and every season after it: 60 days.**
  - **Reasoning (record, don't relitigate without asking again):** cutting
    the live Season 1 short mid-run would damage the trust of users who
    already invested effort under a 91-day expectation set at the start;
    the cadence change is forward-only specifically to avoid that — it
    costs nothing users were already promised.
  - **Still not implemented — this is the real remaining work:** the live
    Season row and any season-length constant/config are untouched.
    Concretely still needs scoping: how `advance_seasons`/
    `transition_season` (database-api-spec.md's Season lifecycle,
    T3.6) knows Season 1 specifically is 91 days while every season it
    creates after that is 60 — a hardcoded one-time exception, a
    `season.length_days` column, or something else. Also needs: the
    Season League point-band recalibration this triggers for Season 2+
    specifically (tech-spec.md §2.5's own T4.18 note), and what T4.17's
    Club Aktif/Club War Record sections do during Season 1, when there
    is no 60-day cadence yet to align to (see T4.17's own note above).
  - Distinct from T4.17: this is a live-data/config change on the
    **currently active** production Season row, not new feature work —
    but T4.17's reset cadences can't actually match the User Season
    cadence they're meant to mirror until this ships.

---

## ~~Deferred from MVP v1~~ CANCELLED PERMANENTLY — Local Leaderboard (T3.2–T3.5)

> **Moved here from Fase 3 on 2026-09-21. ~~Deferred to v1.1 — NOT cancelled.~~**
> ~~Product decision: the local leaderboard is cut from MVP v1 (v1 = Global
> Leaderboard only). It needs high user density to be useful — with few
> early users a kecamatan holds a handful of people and the board is
> empty/uncompetitive, while a Global board already feels "local" at small
> scale. The value appears *after* there are many users; it is not a launch
> prerequisite.~~
>
> **CANCELLED PERMANENTLY, 2026-09-22 (PM sign-off) — supersedes the above.**
> Rationale: scope too broad for the leaderboard logic actually needed, a
> scope decision rather than a density/timing one — will not be
> implemented, ever. The region data collected for this feature (User's
> kecamatan/kabupaten_kota/provinsi, `LEADERBOARD_SCOPE`'s regional
> `scope_type` values) is itself being removed from the schema — see
> tasks/phase-3-season.md T3.1 and database-api-spec.md. Everything below
> is kept verbatim as a historical record only.
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
