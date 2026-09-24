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
  **One club per user — deliberate, decided 2026-09-23** (product-spec.md
  §4.19): avoids cross-Club double-counting in Participation Rate and the
  Club War snapshot. Already enforced by T4.2a's migration.
  **T4.1 extended scope, belum dijadwalkan**: ~~description, privacy/
  visibility, join flow, leave/transfer/delete, member cap — deferred,
  not decided (user-flow.md §2.6 is still an unreconciled draft).~~
  **Scoped 2026-09-23 — product-spec.md §4.24 AC1-AC21** (AC16-AC21 added 2026-09-24): any tier creates
  clubs, description + public/invite-only in v1, public = direct join,
  invite-only = invite code, no request/approval, leave in v1, internal
  leaderboard from existing season points; ~~admin tools and club feed
  deferred.~~ club feed deferred. **Admin tools in scope (revised
  2026-09-23 — T4.8 merged here):** Premium-included, owner/admin of a
  Premium Club only, internal to the club only — minimal viable member
  list + aggregate distance/points, and internal challenges with a target
  distance and a time window (AC11-AC15). **Still deferred:** ~~ownership transfer, club deletion,~~ member
  cap. ~~**Still open (§4.24):** can the owner leave; how admins are
  appointed; club membership on account deletion; where the Club UI
  lives; invite-code visibility/regeneration.~~ **Closed 2026-09-24
  (§4.24 AC16-AC21):** owner transfers ownership or deletes the club (sole
  member) before leaving; owner promotes admins directly; account
  deletion removes membership and hands ownership to the longest-standing
  admin, else member, empty club archived; UI = "Club Saya" in the You
  tab; random regenerable invite codes, no expiry; analytics = totals +
  active members + top-N; challenges = collective distance/duration
  target + deadline, no rewards/points. **Still open:** delete vs archive
  for AC16; analytics period and N; challenge run-counting, concurrency,
  notifications. **Ordering (2026-09-23):**
  Social Feed (T4.15) is built **before** this task (see T4.15).
- **T4.1a — Club: extend the `club` table.** Depends on T4.2a's migration
  (which creates the minimal `club` stub). **Scope**: a **separate, new**
  inert migration — T4.2a's file is not modified — adding `description`,
  a privacy column (`public` | `invite_only`), and an invite code (unique,
  required only for `invite_only`), with RLS unchanged (already
  deny-all). **Plus (2026-09-23, admin tools):** a new internal-challenge
  table ~~(club, name, target distance, start/end)~~ (club, name, target
  type `distance` | `duration`, target value, deadline — revised
  2026-09-24) with RLS enabled and no grants. Analytics needs no table —
  aggregated from existing runs. **Plus (2026-09-24):** an archived marker
  on `club` (AC18). Reviewed before apply. **Reference**: product-spec.md
  §4.24 AC2, AC5, AC13, AC18, AC20.
- **T4.1b — Club: backend.** Depends on T4.1a. **Scope**: create (any
  tier, creator = owner), join public directly, join invite-only with the
  code, leave, browse/search public clubs, and the internal leaderboard
  read (members ranked by existing season points). One-club-per-user is
  already enforced by `club_member`'s primary key (T4.2a). **Plus admin
  tools (2026-09-23):** analytics read (member list, aggregate
  distance/points) and create/read internal challenges with progress —
  both gated server-side on "caller is owner/admin AND the club is a
  Premium Club" through T4.20b's check (so, like T4.2b, blocked until
  T4.20 is implemented), and never readable by non-members. ~~Owner-leave,
  admin appointment, account-deletion handling and the admin-tools
  details (aggregate period, counting rule, concurrent challenges,
  notifications) wait on §4.24's open points.~~ **Plus (2026-09-24):**
  transfer ownership; owner-only promote/demote admin; delete (sole
  member) — delete-vs-archive still open; regenerate invite code
  (owner/admin); analytics adds active members + top-N; challenges use a
  distance or duration target and a deadline, never touching points; and
  the account-deletion hook — T2.22's `account-deletion.ts` must remove
  the member and run owner succession (AC18). Analytics period/N and
  challenge counting/concurrency/notifications still open. **Reference**:
  product-spec.md §4.24 AC1-AC9, AC11-AC21.
- **T4.1c — Club: iOS UI.** Depends on T4.1b. **Scope**: create, browse,
  join (direct or code), leave, club page with the internal leaderboard,
  **and (2026-09-23) the admin-tools screens** — analytics and creating/
  viewing internal challenges — shown only to owner/admins of a Premium
  Club; members see challenge progress, nobody outside the club sees
  anything. ~~Blocked on where the Club UI lives (§4.24 open point).~~
  Lives in a **"Club Saya"** section of the **You** tab (AC19, decided
  2026-09-24); also transfer ownership, promote admin, regenerate invite
  code. Not wireframed yet (screen-inventory.md §4). **Reference**:
  product-spec.md §4.24 AC1-AC21.
- **T4.2 — Club War.** Depends on T4.1. **CONFIRMED TO BUILD 2026-09-23**
  (was "nice to have v2+") — see product-spec.md §4.19 for the base decision
  (max 3 clubs/war, self-serve by Premium Club owner/admin, ADR-0014's
  event-scale rule). ~~vs. genuinely open (mechanics, win condition,
  duration).~~ **Mechanism finalized 2026-09-23** (§4.19 AC1-AC13): Participation
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
  **Reference**: product-spec.md §4.19 AC1-AC13, §4.20
  Section 2 (Club War Record's own data needs).
- **T4.2b — Club War: backend API.** Depends on T4.2a. **Scope**: create
  a challenge (target 1-2 specific clubs), accept/decline per invited
  club, **challenge dissolution on decline or 24h timeout (AC7 — no
  Club War Record write, distinct from and not a "forfeit")**, a
  precompute job scoring Participation Rate per war-entered member over
  the 48-hour window once a war is actually active (reusing §4.20
  Section 1's metric, not reimplementing it), the tie-break and
  total-inactivity forfeit rules (AC5-AC6 — active-war-only, do write
  the Club War Record), and an endpoint to read the Record.
  **Permission check (added 2026-09-23)**: only the owner or an admin of a
  *Premium Club* may send a challenge — "Premium Club" = the Club's
  **owner** has an active Premium subscription (§4.19 base decisions);
  an admin sending the challenge does not need Premium themselves. The
  participation check uses §4.20 Section 1's activity threshold
  (~~`validated`~~ **`validated`/`flagged`/`approved`**, corrected 2026-09-23,
  + ADR-0009 gate).
  **Member who leaves mid-war — DECIDED 2026-09-23 (PM): STILL COUNTED.**
  A member who leaves their club after the war went `active` still counts
  toward that club's Participation Rate for that war: the participant
  snapshot (`club_war_participant`, taken at `pending → active`) is final
  for that war and is **not** edited when someone leaves (§4.19 AC11).
  ~~(T4.2a's migration comment still calls this "genuinely open" — stale
  since 2026-09-23; update it with the banner when the migration is
  applied.)~~ T4.2a's migration comment corrected 2026-09-23 (comment-only).
  **War results are final at the 48-hour mark** (§4.19 AC13): a counted
  `flagged` run rejected later does not revise the recorded win/loss — no
  re-computation path is needed.
  **Premium lapse (decided 2026-09-23)**: checked on demand, never polled
  (§4.23 decided #10), at three points — challenge sent (owner not Premium
  → refuse), `pending → active` (inviter's owner lapsed → dissolve, no
  record, §4.19 AC12), war result at the 48h mark (inviter's owner lapsed
  → inviting club forfeits, recorded loss, §4.19 AC10). **Inviting club
  only** — invited clubs are never checked. "Lapsed" = Apple status `2`;
  billing retry and grace period count as Premium. ~~**Unmet dependency, flagged not
  resolved**: no Premium subscription system exists in the codebase yet
  (verified 2026-09-23 — no StoreKit/entitlement/subscription code or
  table), and no backlog task covers subscription infrastructure itself
  (T4.4–T4.7 are individual Premium *features*, not the subscription
  system they'd all sit on). T4.2b cannot implement this check until
  that exists.~~ **Depends on T4.20 (Premium subscription infrastructure,
  scoped 2026-09-23, product-spec.md §4.23)** — the Premium Club check
  goes through T4.20b's server-side check (Apple's live status, never a
  client flag). Blocked until T4.20 is actually **implemented**, not just
  scoped — and T4.20b is itself blocked in full by the Apple Developer
  Program (verified 2026-09-23, see T4.20b). Also implements §4.19
  AC10-AC13. **Reference**: product-spec.md §4.19 AC2-AC13, §4.23, ADR-0013
  (precompute-not-live-derive pattern), §4.20 Section 1.
- **T4.2c — Club War: iOS UI.** Depends on T4.2b. **Scope**: send a
  challenge (Premium Club owner/admin only), accept/decline an incoming
  challenge, view an active war's status/score, view the Club War Record
  (lives under **"Club Saya"** in the You tab, following §4.24 AC19 —
  2026-09-24; shares a screen with §4.20's Club Global Leaderboard, not a separate
  screen — no `screen-inventory.md` entry added by this task itself).
  **Reference**: product-spec.md §4.19 AC1-AC13, §4.20.
- **T4.3 — Matchmaking between clubs.** Depends on T4.1. ~~Still Non-goal,
  no decided shape.~~ **Confirmed to build (2026-09-23, PM), separate from
  Club War; direction: suggestion-only** — the system suggests candidate
  opponents, the club still sends the challenge by hand (§4.19), no forced
  pairing or auto-start. Not scoped in detail — needs its own scoping
  session.
- **T4.4 — Monetization: seasonal pass.** Scope note (2026-09-23, PM —
  direction set, not AC-level):
  - Same thing as user-flow.md §2.8 "Seasonal Cosmetic Reward": when a
    season ends, **Premium** users are **automatically** granted cosmetics
    (profile frame, season badge) based on their season rank. **Not a
    separate purchase** — part of Premium.
  - Freemium keeps its season result (Fase 3, free) with no cosmetic.
  - Not decided yet: which ranks qualify and what exact cosmetics each gets
    (the draft only says "rank tertentu"). Hooks onto season end (T3.8's
    season results). Depends on T4.20.
- **T4.5 — Monetization: advanced statistics.** Scope note (2026-09-23,
  PM):
  - Computed **on the device from Core Data**, not on the server.
  - Metrics exactly as drafted in user-flow.md **§2.5** (the prompt that
    set this said §2.8 — §2.8 is the seasonal reward): weekly/monthly pace
    trend chart, personal-record history (longest distance, fastest pace,
    with date and run context), period comparison (this month vs last).
    Draft's Freemium view: lifetime totals only.
  - Consequence of on-device: stats only cover runs present in this
    device's Core Data (a new device/reinstall starts from whatever is
    stored locally). The Premium gate is the StoreKit local entitlement
    (§4.23 hybrid) — nothing server-side to check. Depends on T4.20c.
- **T4.6 — Monetization: exclusive badge.** Scope note (2026-09-23, PM):
  - Badge sources, as drafted: the Premium subscription itself,
    achievements, and season rank (user-flow.md §1, §2.4).
  - Shown on profile and on feed posts (draft §1).
  - **Gap:** "achievement" isn't defined anywhere — no achievement system
    exists in the spec or code. Needs defining before this is scoped.
    Season-rank badges overlap T4.4's season badge — keep one mechanism.
    Depends on T4.20.
- **T4.7 — Monetization: premium profile.** Premium pricing decided
  2026-09-23 ($7.99/mo + App Store Connect regional tiers, product-spec.md
  §5) — applies to whichever of T4.4–T4.7 eventually ship, not scoped to
  one of them specifically. **v1 packaging (2026-09-23): monthly only, no
  annual plan, no free trial** — deliberate (product-spec.md §4.23).
  Scope note (2026-09-23, PM):
  - **Exactly three things:** profile photo, bio, alternative app icon.
    Nothing more.
  - Profile photos need storage and moderation — a real concern, recorded
    for later, **not** a blocker for this scope.
- **T4.4–T4.7 all depend on T4.20** (added 2026-09-23): each is a Premium
  *feature* and had silently assumed a subscription system existed. None
  does yet — see T4.20 below.
- ~~**T4.8 — B2B dashboard: running club.** Unchanged — still a self-serve
  tool, unlike T4.9 below. **Direction (2026-09-23, PM): a web dashboard,
  separate from the mobile app, sold separately from Premium $7.99 (not
  bundled).** Price and exact features not scoped — needs its own scoping
  session. (Club admin tools deferred from T4.1 land here, not twice.)~~
  **MERGED into T4.1, 2026-09-23 (PM).** No separate B2B product and no
  web dashboard: club admin tools (analytics, internal challenges) are now
  part of T4.1, a Premium feature included in the $7.99 subscription, for
  owners/admins of a Premium Club, internal to the club only
  (product-spec.md §4.24 AC11-AC15). Task number T4.8 retired, not reused.
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
  **Broken into sub-tasks 2026-09-23 on explicit PM instruction** (same exception as T4.2, T4.14,
  T4.20) — Scope + Reference only, no DoD; the phase itself is still not scheduled. ~~Two open points
  found while doing it (not decided here): where "Social tab → Events sub-tab" lives, since no Social
  tab exists (the app's tabs are Track / You / Ranks — "social" was the old placeholder name for
  Ranks, `RootTabView.swift:48`); and where the "Join X Runners" count comes from, since sponsored
  registration happens off-platform and announcement-only events have no registration at all.~~
  **Both decided 2026-09-23 (PM):** Events is a sub-tab of **Ranks** (§4.21 AC6); the "Join X
  Runners" overlay is **removed** (AC7).
- **T4.9a — Events: `event` table.** Depends on T4.9. **Scope**: one table per §4.21's rough data
  model — `id`, `title`, `image_url`, `description`, `type` (`sponsored` | `announcement`),
  `external_url` (required when `sponsored`, null when `announcement` — enforce with a CHECK),
  `sponsor_name` (sponsored only), `starts_at`, `ends_at`, `is_active`. **No region column** (§4.21
  AC4). RLS enabled with no grants. Where the image file itself is hosted is decided in this task.
  ~~Any column for the "Join X Runners" count waits on that open point.~~ No participant-count
  column — the overlay was removed (§4.21 AC7). Written inert, reviewed before
  apply. **Reference**: product-spec.md §4.21 data model, AC1, AC4.
- **T4.9b — Events: staff tooling + read endpoint.** Depends on T4.9a. **Scope**: internal-only
  create/edit/activate/deactivate for Laju staff — an admin CLI script is §4.21's recommendation
  (its "Should"), never a self-serve surface (§4.21 AC5 Must, ADR-0014). A read endpoint returning
  every active Event to every signed-in user, no region or other eligibility filter (AC4). No
  registration or reward logic of any kind (AC2-AC3). **Reference**: product-spec.md §4.21 AC2-AC5.
- **T4.9c — Events: iOS feed + detail.** Depends on T4.9b. **Scope**: an **Events sub-tab inside
  the Ranks tab** (AC6) — card feed (full-width image, **no** participant count, AC7), detail view,
  and for `sponsored` events opening `external_url` externally (AC2). **Includes moving the
  location-permission lock** from the whole Ranks tab (`LeaderboardView.swift` today) down to the
  leaderboard sub-tab only, so Events is never locked (AC8, AC4). ~~Blocked on the two open points
  above (which tab; where X comes from), and~~ Not wireframed yet (screen-inventory.md §4 excludes
  Fase 4). **Reference**: product-spec.md §4.21 AC1-AC2, AC4, AC6-AC8.
- **T4.17 — Club Global Leaderboard.** Depends on T4.1 (Club must exist)
  and, for its Section 2, T4.2 (Club War must exist — Section 2 has
  nothing to rank without match data). **CONFIRMED TO BUILD 2026-09-23**
  — see product-spec.md §4.20 for the two-section spec (Club Aktif /
  Club War Record). Both sections' 60-day reset cadence is **resolved by
  T4.18 below: applies starting Season 2, not from now** — Season 1
  (currently live, 91 days) has no 60-day cadence to align to yet. ~~so
  this task's own scoping must decide what either section does during
  Season 1 specifically (T4.18 doesn't answer that, only the User
  Season's own length).~~ **Decided 2026-09-23 (PM): neither section
  resets during Season 1** — one period from launch to Season 2 start.
  Club Aktif's 60-day reset re-confirmed (not rolling 30 days). AC1-AC12
  in §4.20. ~~Still open there: Club War Record ordering, Club Aktif roster
  edge cases, "never fought" after a reset.~~ All three decided 2026-09-23
  (AC10 net wins, tie → more wins; AC11 live roster, Club Aktif only;
  AC12 per-period). No open points left in §4.20. Sub-tasks below.
- **T4.17a — Club leaderboard: precompute tables.** Depends on T4.2a
  (`club`/`club_member`/`club_war_club` must exist). **Scope**: storage
  for both sections' precomputed results, each row tied to its period
  (Season 1 = launch→Season 2 start; afterwards one 60-day period per
  Season), same rebuild-per-run shape as `leaderboard_entry` (ADR-0013);
  RLS enabled with no grants. Written inert, reviewed before apply (same
  gate as T4.2a). **Reference**: product-spec.md §4.20 AC1-AC2, AC8-AC9.
- **T4.17b — Club leaderboard: two precompute jobs + read endpoint.**
  Depends on T4.17a; the Club War Record job also needs T4.2b (wars must
  exist). **Scope**: Club Aktif job — Participation Rate per club with the
  shared activity threshold, the 10-member minimum ("Belum Cukup
  Data") and the **live** roster at run time (AC11); Club War Record job —
  aggregate `club_war_club.outcome` over wars with `club_war.status =
  'ended'` only, clubs with no ended war in the period omitted (AC12),
  ordered by net wins, tie → more wins (AC10). Period boundaries depend on
  Season rows. ~~Blocked on §4.20's open ordering rule for Club War
  Record.~~ **Reference**: product-spec.md §4.20 AC1-AC12, §4.19 AC13.
- **T4.17c — Club leaderboard: iOS UI.** Depends on T4.17b. **Scope**: one
  screen with the two sections, the "Belum Cukup Data" state, clubs
  without wars absent from Club War Record; shares its Club War Record
  view with T4.2c. Not wireframed yet (screen-inventory.md §4 excludes
  Fase 4). **Reference**: product-spec.md §4.20 AC3-AC6.
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
  Scope note (2026-09-23, PM):
  - **"Real-time" does NOT mean updated on every run.** The cache follows
    the existing 15-minute precompute — consistent with ADR-0013's "never
    derive live on read". No per-run instant updates.
  - Redis provider: an implementation decision for later, not a design
    blocker.
  - Worth knowing: with freshness unchanged, the gain is taking read load
    off Postgres, not fresher rankings — the "real-time" in this task's
    title no longer describes it, and architecture.md §4's original
    reason (freshness) isn't the reason any more.
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
  Scope note (2026-09-23, PM):
  - **Live Activity content** = the same three values as the Apple Watch
    (product-spec.md §4.22): distance, pace, elapsed time.
  - **HealthKit: write only** — each finished run is recorded to Apple
    Health; nothing is read from Health in v1. One direction, smaller
    scope. (Matches user-flow.md §2.10's draft, which also lists
    *calories* — Laju doesn't compute calories today, so that field isn't
    covered by this decision.)
  - The existing gate is unchanged: do not start until Fase 1–3 have
    shipped (T1.17, Fase 1's gate, is still open).
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
  ~~**Still not a real task (no DoD written)** — blocked on whether
  phone-free tracking is wanted at all (even as a later phase); that
  answer changes the size of the work by an order of magnitude, same
  category of blocker as T4.9/§4.21's "what is an event."~~
  **Apple Watch v1 shape finalized 2026-09-23** (§4.22 AC1-AC7): mirror-only
  (confirmed; phone-free stays open, NOT roadmapped as v2), live metrics +
  pause/stop from the watch, no start from the watch, iPhone always the full
  primary flow, real-time streaming. Blocker resolved for Apple Watch;
  Garmin/Huawei still unscoped. Sub-tasks below.
- **T4.14a — Apple Watch v1: phone-side relay.** Depends on T4.14 (shape
  decided). **Scope**: a `WatchConnectivity` session on the iPhone that
  streams the in-progress run's already-computed distance/pace/elapsed time
  to the watch, and receives pause/resume/stop commands from the watch and
  routes them through the **same** run-control path the phone's own buttons
  use (not a parallel path). Watch disconnect must never affect the phone's
  run. The update interval (per second vs per GPS point) is decided here, as
  an implementation detail. **Reference**: product-spec.md §4.22 AC1-AC4,
  AC6-AC7.
- **T4.14b — Apple Watch v1: watchOS target + UI.** Depends on T4.14a.
  **Scope**: new watchOS target (XcodeGen `project.yml`), a screen showing
  live distance/pace/elapsed time, and pause/resume/stop controls — no start
  control. **Reference**: product-spec.md §4.22 AC1, AC3, AC5.
- **T4.14c — Garmin companion.** Placeholder only — **not scoped, not
  decided** (§4.22 Q4, 2026-09-23). Needs its own scoping pass after Apple
  Watch ships; separate stack (Connect IQ SDK, Monkey C). No AC exists.
- **T4.14d — Huawei Watch companion.** Placeholder only — **not scoped, not
  decided** (§4.22 Q4, 2026-09-23). Needs its own scoping pass after Apple
  Watch ships; separate stack (HarmonyOS or Wear OS, depending on model). No
  AC exists.
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
  **Revisited explicitly 2026-09-23 (PM): Social Feed is built BEFORE
  Club (T4.1)** — still Fase 4, but ordered ahead of Club, reversing the
  implied "same phase, Club alongside/first" reading above. Work order
  becomes T4.15 → T4.1 → T4.2 (Club War needs Club). Not scoped in detail
  — needs its own scoping session. **Consequence to settle then:** the
  draft's audience options (user-flow.md §2.7: Public / *Circle saja* /
  Private) include a club-only audience that can't exist yet if Social
  Feed ships before Club; likewise T4.1's club feed (§4.24, deferred)
  waits on this.
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
  - ~~**Still not implemented — this is the real remaining work:** the live
    Season row and any season-length constant/config are untouched.
    Concretely still needs scoping: how `advance_seasons`/
    `transition_season` (database-api-spec.md's Season lifecycle,
    T3.6) knows Season 1 specifically is 91 days while every season it
    creates after that is 60 — a hardcoded one-time exception, a
    `season.length_days` column, or something else. Also needs: the
    Season League point-band recalibration this triggers for Season 2+
    specifically (tech-spec.md §2.5's own T4.18 note).~~
  - **Implementation scoped 2026-09-23 (PM decisions, final):**
    1. **Season 2 (and later seasons) are created manually** with the
       existing `backend/scripts/season.ts create "<name>" <start> <end>`,
       giving a 60-day period — no new auto-creation code. This dissolves
       the old "how does `advance_seasons` know 91 vs 60" question:
       `advance_seasons` never creates seasons (it only activates an
       existing `upcoming` row once `start_at` passes, verified in
       `20260921180000_season_lifecycle.sql`), and every season row
       already carries its own `start_at`/`end_at` — no length constant
       exists anywhere to change.
    2. **Overrun must not be silent.** Today `overrun` is only a row the
       function returns inside pg_cron — nothing reads it (verified: no
       alerting code). **Small tech-debt todo, part of this task:** emit a
       clear warning-level log when `overrun` is detected (in
       `advance_seasons` and/or `season.ts`), so a missed Season 2 is
       visible. Nothing more complex required.
    3. **League bands (`backend/lib/season-league.ts`) are recalibrated
       after real Season 2 data, not before** — no guessing numbers now.
       Known consequence: Season 2 runs on bands calibrated for a ~91-day
       season, so with ~34% less time to earn points, Season 2's league
       spread will skew toward the lower leagues until recalibration.
  - **Also stale, fix with the overrun todo:** `season.ts`'s header usage
    example creates "Season 2 — 2026" as `2026-12-01 → 2027-02-28` (~90
    days) — it contradicts the 60-day decision and is the exact command
    someone would copy. Code file, not changed in the docs-only pass.
  - **Operational deadline stands:** Season 2 must be created before
    2026-11-30 (HANDOFF.md §3). ~~, and what T4.17's
    Club Aktif/Club War Record sections do during Season 1, when there
    is no 60-day cadence yet to align to (see T4.17's own note above).~~
    (T4.17's Season 1 behavior was decided 2026-09-23 — no reset during
    Season 1, product-spec.md §4.20 AC9 — so it's no longer open here.)
  - Distinct from T4.17: this is ~~a live-data/config change on the
    **currently active** production Season row~~ an operational step
    (creating the Season 2 row by hand) plus a small logging change — the
    currently active Season 1 row is not touched — not new feature work —
    but T4.17's reset cadences can't actually match the User Season
    cadence they're meant to mirror until this ships.
- **T4.20 — Premium subscription infrastructure.** Added 2026-09-23 (PM
  decision) — see product-spec.md §4.23 (AC1-AC14). The foundation every
  Premium-dependent item sits on: T4.2b's Premium Club check, §4.5 AC4's
  league gating, T4.4-T4.7. Built **before** those, per PM. Numbered
  T4.20, not T4.19, to avoid confusion with product-spec §4.19 (Club War).
  Hybrid: StoreKit 2 on device for UI, backend as source of truth.
  Monthly-only $7.99, no annual, no trial. App Store Server Notifications
  are target design but **blocked** by the Apple Developer Program
  (HANDOFF.md §4) — not built now. **Verified 2026-09-23: the block is
  wider than notifications** — T4.20b (all App Store Server API calls)
  is blocked in full, and T4.20c's real App Store products need App
  Store Connect too. Only T4.20a (schema) is buildable before enrollment.
- **T4.20a — Premium: `subscription` table.** Depends on T4.20. **Scope**:
  append-only `subscription` table (`user_id`, `original_transaction_id`,
  `product_id`, `status`, `expires_at`, `environment`), same ledger pattern
  as `point_transaction` (ADR-0013) — status changes are new rows; RLS
  enabled with no grants, per `20260919150457_enable_rls_deny_anon.sql`.
  Written inert and reviewed before apply, same gate as T4.2a.
  ~~**Blocked on one open point (2026-09-23):** whether `user_id` is
  nullable depends on the account-deletion anonymization mechanism still
  open in §4.23. Decide before writing the migration.~~ **Unblocked
  2026-09-23 (PM chose option (b)):** `user_id` is **NOT nullable** — a
  regular FK to `user`, exactly like `point_transaction.user_id`. Account
  deletion never touches `subscription` rows; the anonymized `user` row
  does the disconnecting. Ready to be written as an inert migration (same
  gate as T4.2a) — not written yet. **Reference**: product-spec.md §4.23
  decided #2, #13, AC6, AC14.
- **T4.20b — Premium: backend verification + status endpoint.** Depends
  on T4.20a. **Scope**: verify transactions with the App Store Server API
  before recording them (AC5); enforce one Apple ID = one active Premium
  Laju account via `appAccountToken` + `GET /inApps/v2/history/{anyTransactionId}`
  (AC7); an endpoint returning the caller's Premium status; the shared
  server-side "is this user Premium" check T4.2b and §4.5 AC4 call (AC4).
  ~~**Flagged**: calling the App Store Server API needs an In-App Purchase
  key from App Store Connect — believed to require the paid Apple
  Developer Program too, which would make this blocked for the same
  reason as notifications, not only the notifications part. Needs
  checking before this task starts.~~ **Verified 2026-09-23 — BLOCKED IN
  FULL by the Apple Developer Program**, not only the notifications part:
  every App Store Server API request needs a JWT signed with an In-App
  Purchase key generated in App Store Connect (Apple docs, "Creating API
  keys to authorize API requests"), and App Store Connect is not available
  to free accounts (Apple's membership comparison). So none of this task —
  verification, the one-Apple-ID rule, the on-demand Premium check — can be
  built or tested until enrollment. Also does the on-demand checks of
  §4.23 decided #10 (Apple's live status via
  `GET /inApps/v1/subscriptions/{anyTransactionId}`, since `expires_at`
  alone can't tell grace period from expired), and the AC7 refusal
  message. **Reference**: product-spec.md §4.23 AC4-AC5, AC7, AC10-AC11.
- **T4.20c — Premium: iOS StoreKit 2.** Depends on T4.20b (to sync
  purchases to the backend). **Scope**: product load and purchase flow
  with `appAccountToken = user.id` (AC1-AC2), immediate Premium UI from
  StoreKit's local verified entitlement (AC3), Restore Purchases on any
  device (AC8), and — added 2026-09-23 — before starting a purchase, if
  this device's Apple ID already has an active Laju subscription belonging
  to another Laju account, refuse with *"Apple ID ini sudah punya
  langganan Laju Premium aktif di akun lain."* (AC7); no transfer flow
  (AC12). Needs a new StoreKit configuration; real products in App Store
  Connect need the paid Developer Program (verified 2026-09-23 — App Store
  Connect is paid-only). Whether local `.storekit` testing in Xcode works
  without it is still unverified. **Reference**: product-spec.md §4.23
  AC1-AC3, AC7-AC8, AC12.

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
