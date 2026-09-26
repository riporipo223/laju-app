# Laju — Wireframe Spec

Created 2026-09-17. For each screen that still needs design work, this lists the elements that must be present, their information hierarchy, and every state that needs its own treatment. **Textual, not visual** — this is the checklist to wireframe *against*, not a description of a layout that already exists.

Read alongside [design-notes.md](./design-notes.md) for tokens (colors, type, components) and [screen-inventory.md](./screen-inventory.md) for status and ordering. Every element below traces to an acceptance criterion in [product-spec.md](../01-product/product-spec.md) §4 — nothing here is a new feature.

**How to read the hierarchy column:** elements are listed in priority order — #1 is what the eye should land on first. If a wireframe makes #3 louder than #1, the wireframe is wrong regardless of how it looks.

---

## 1. Run Tracking (screen 5) — base identity screen

**Already built and restyled** onto the black+lime system (2026-09-14). This section is therefore a *reference* for what the screen must contain and a checklist for its states — not a backlog item. It is listed first because it sets the visual language every other screen inherits, so anything new should be judged against it.

**Context that constrains the design:** the user is moving, often in sunlight, possibly glancing at the phone for under a second while running. Legibility at a glance beats density. This is also the only screen where a *wrong* reading has real cost — a runner who misreads pace changes their effort.

### Elements

| # | Element | Notes |
|---|---|---|
| 1 | **Live distance** — hero number | The primary number. `Hero number` type token (56pt heavy rounded, monospaced digits), `accent` lime |
| 2 | **Duration** and **current pace** | Secondary heroes, `textPrimary` white, not lime — only one thing is lime per screen |
| 3 | **Live map with route polyline** | `accent` stroke with soft glow. Custom position annotation only — never `showsUserLocation` (ADR-0011) |
| 4 | **Start / Pause / Resume / Stop controls** | Primary pill for Start; secondary pill for Pause/Resume; destructive pill for Stop confirmation. Min 52pt tall — tapped while moving |
| 5 | **Splits list (per km)** | Appears as km boundaries are crossed. Partial final split clearly marked, never rounded or hidden (AC 4.10.2) |
| 6 | **GPS status banner** | Only visible when signal is degraded. Deliberately un-animated — a flicker here reads as an error (design-notes §4) |
| 7 | **Overlay buttons → History, Profile** | Floating, must not compete with the hero numbers or block the map |

### States

- **Idle (pre-run)** — map centred on user, one primary Start button. Everything else absent or dimmed. This is the app's default screen; it should feel like an invitation, not a dashboard.
- **Active** — as above, all stats live.
- **Paused (manual)** — stats frozen and visibly frozen. The user must be able to tell at a glance that nothing is being recorded.
- **GPS degraded (5a)** — banner present, stats continue. Must not look like an error state; tracking is still working.
- **Permission: While-Using (5c)** — persistent banner warning that tracking stops when the screen locks, with a "Buka Pengaturan" action (AC 4.15.2).
- **Permission: Denied (5d)** — stronger treatment; the core loop is unavailable. Still offers the Settings deep link (AC 4.15.3).

---

## 2. Run Summary (screen 6) — the reward moment

**Built and restyled** (2026-09-14), including the confetti burst. **Highest-stakes screen in the product** — product-spec §1's entire hypothesis is that this moment feels rewarding enough to bring the user back. The outstanding work here is *states*, not the base layout: 6d and 6e do not exist yet, and 6a/6b/6c deserve a second look.

### Elements

| # | Element | Notes |
|---|---|---|
| 1 | **Points earned** | The reward. Hero number, `accent` lime. Must appear within 2s of Stop (AC 4.3.1) — design cannot depend on a network call |
| 2 | **Level + progress bar** | If a level-up happened, this is co-primary with #1 — see state 6a |
| 3 | **Distance, duration, avg pace** | Stat-card grid, `textPrimary` |
| 4 | **Static route map** | Whole route, `accent` polyline (AC 4.9.1) |
| 5 | **Splits list** | Per km, with the partial final split marked |
| 6 | **Elevation gain / loss** | Two values (AC 4.12.1) |
| 7 | **Streak indicator** | Current streak days; ties visually to Profile's streak grid |
| 8 | **Dismiss / back to Home** | Single clear exit |

### States

- **Default** — as above.
- **Level-up (6a)** — the number and badge should *feel earned*. Gets deliberate motion (design-notes §4). Level-up reuses `accent`, deliberately not a separate success green — levelling up is "more lime", not a new color.
- **Confetti** — fires on Finish. Full spec in [prototyping-reference.md](./prototyping-reference.md) §2.
- **Zero-GPS-points (6c)** — run recorded but no route (indoor, or permission lost mid-run). Map area needs an explicit empty state, not a blank grey box (AC 4.9.3).
- **Streak-reminder prompt (6b)** — contextual permission ask, only when `streakDays >= 1` and permission is `.notDetermined`. Must explain *why* before the system prompt appears (AC 4.16.1). Should feel like an offer, not an interruption of the reward moment — consider placing it below the fold, after the points have landed.
- **Flagged / "sedang diverifikasi" (6d, Fase 2)** — points shown are provisional. Uses `warning` amber, the token reserved for exactly this since design-notes was written. Must not read as an accusation — the copy is about verification in progress, not cheating detected.
- **Resolution changed (6e, Fase 2)** — a previously-flagged run resolved later, and **points may have gone down**. This is expected behavior, not an error, and the design must communicate a decrease without reading as a bug or a punishment.

---

## 3. Run History (screen 7)

**Built and restyled** (2026-09-14) — dark card rows with the top-accent-line signature. Reference and state checklist only.

| # | Element | Notes |
|---|---|---|
| 1 | **Run rows, most recent first** (AC 4.18.1) | Each row: date, distance, duration, pace, points |
| 2 | **Route thumbnail per row** | Static map per run (AC 4.9.2) |
| 3 | **Empty state (7a)** | No runs yet. Must be distinct from "still loading" |

Deliberately **not** animated — plain list semantics (design-notes §4). Displayed values must match stored Core Data values exactly (AC 4.18.2); no rounding that makes history disagree with the summary the user already saw.

---

## 4. Profile / Level (screen 8)

Already restyled. Listed for completeness and because it owns the streak grid that Run Summary references.

| # | Element | Notes |
|---|---|---|
| 1 | **Current level + progress bar** | Points to next level visible (AC 4.4.3) |
| 2 | **Streak grid** | 7-column heatmap. Filled `accent` circle = qualifying day, hollow `hairline` = miss, today gets a thin `accent` ring even when unfilled |
| 3 | **Lifetime totals** | Total points, total runs |
| 4 | **Recent runs** | Short list, links into Run History |

Fase 2 adds: account deletion entry point (screen 14).

---

## 5. Global Leaderboard (screen 11, Fase 2)

Not built. **Introduces the one genuinely new pattern in the product** — a dense repeating row. Worth designing early even though T2.20 is some way off.

| # | Element | Notes |
|---|---|---|
| 1 | **Own rank, pinned** | Always visible regardless of scroll position (AC 4.5.1). This is what the user opens the screen for |
| 2 | **Top N rows** | Rank number, display name, points. Dense but legible |
| 3 | **Season context** | Which season this is scoped to (AC 4.5.3) |
| 4 | **Freshness indicator** | Data is precomputed, up to 15 min stale (AC 4.5.2). The user should not think it is live |

### States

- **Default** — populated.
- **Loading** — first fetch.
- **Offline / stale** — cached snapshot shown. Must be honest that it is cached.
- **User not yet ranked** — has an account but no qualifying runs.
- **League view (future, not designed yet)** — a "liga sendiri / semua liga" toggle: Freemium sees own league only, Premium unlocks all leagues, both **within Global** (product-spec.md §4.5 AC4, revised 2026-09-21; previously the Freemium/Premium split was Global-vs-Local). "Tier" means **Season League** — Bronze / Silver / Gold / Platinum, from points earned this season, reset each season (tech-spec.md §2.5); not Level, not Rank. Needs the Premium tier, which is not built — no wireframe until it is scheduled.
- **No Global/Local toggle in v1.** The Local Leaderboard is deferred (§6); this screen is the whole leaderboard.

**Design note:** rank 1-3 will invite podium treatment (design-notes §5 references #5's podium). Keep it restrained — the pinned own-rank row is the emotionally important element for the 99% of users not in the top 3, and it must not be visually subordinate to a podium they will never be in.

---

## 6. Local Leaderboard (screen 12) — ~~DEFERRED to v1.1 / Fase 4~~ **CANCELLED PERMANENTLY 2026-09-22**

> ~~**Not part of MVP v1 (product decision, 2026-09-21).** Kept as a reference for when the feature is scheduled; no design work is needed now. Reason: it needs high user density to be useful — with few early users a kecamatan is nearly empty. Tasks: T3.2–T3.5 in tasks/phase-4-backlog.md. It used to be labelled "Fase 3".~~
>
> **CANCELLED PERMANENTLY 2026-09-22 (PM sign-off)** — not deferred, never to be scheduled. Reason given: scope too broad for the leaderboard logic needed. This section is a historical record; do not design against it. See product-spec.md §4.6.

Screen 11 plus scope selection. Design 11 first.

| # | Element | Notes |
|---|---|---|
| 1 | **Scope filter** — kecamatan / kabupaten-kota / provinsi | Three levels (AC 4.6.1). Chips or segmented control |
| 2 | **Leaderboard rows** | Same row component as screen 11 |
| 3 | **Current scope label** | Which region, made unambiguous |

### States

- **Insufficient data (12a)** — "belum cukup data" for a low-density region (AC 4.6.2). Expected right after season start, **not an error** — should suggest the next-wider scope rather than dead-ending.

---

## 7. Season Info (screen 13, Fase 3)

| # | Element | Notes |
|---|---|---|
| 1 | **Countdown to season end** (AC 4.7.2) | The urgency driver |
| 2 | **Current season rank** | Reuses the leaderboard row component |
| 3 | **Past seasons' final ranks** (AC 4.7.3) | Retained and viewable after a season ends |
| 4 | **What resets vs what does not** | Rank resets, lifetime level/points do not (AC 4.7.1). Explicitly explained — this is the single most confusing mechanic in the product, and a user who thinks their level reset will churn |

---

## 8. Region picker (screen 10, Fase 2/3) — **CANCELLED 2026-09-22, never to be built**

> **CANCELLED PERMANENTLY 2026-09-22 (PM sign-off).** Decision D1 (region mandatory) is reversed:
> region is removed entirely from onboarding and the database, not redesigned. The cascading picker
> specified below will never be built, and the "why we ask" copy problem (item 4) dissolves with the
> question itself. The existing free-text region fields in `OnboardingProfileStep` are being deleted
> (Task C). Everything below is a historical record — do not design or build against it. Replacement
> for leaderboard access: a location-permission gate, product-spec.md §4.5 AC5.

> **Interim implementation (2026-09-21):** the app already has a profile step (`OnboardingProfileStep`) with the username and the three region fields as **plain free-text fields** — there is no region catalog to pick from. It is what makes the app call `POST /api/profile/complete`. The cascading picker specified below (T3.1) replaces those three fields; until then the same place can be typed several ways, which the deferred Local Leaderboard will have to normalize.

Three-level cascade: provinsi → kabupaten-kota → kecamatan. Fiddly enough that working it out on paper before it is coded will save real time.

| # | Element | Notes |
|---|---|---|
| 1 | **Three dependent selectors** | Selecting a parent filters the child. Order top-down |
| 2 | **Search within each level** | Indonesia has thousands of kecamatan; a plain picker list is unusable |
| 3 | **Confirmation of full selection** | All three must be set before proceeding (AC 4.1.2) |
| 4 | **Why this is being asked** | *Copy needs a re-write (2026-09-21):* the original reason — "region determines local leaderboard placement, not changeable per-run (AC 4.6.3, anti leaderboard-shopping)" — no longer describes any v1 feature, because the Local Leaderboard is deferred. Region stays **mandatory** (D1 final, product-spec.md §4.1), so the copy must say honestly what it is for — e.g. "for regional rankings coming later" — and must not promise a feature the user cannot see |

### States

- **Nothing selected** (initial), **partial selection** (parent chosen, child pending), **complete**, **search with no results**.

**Blocking behavior:** this screen blocks first run submission. Design it so that feels like setup, not a paywall.

---

## 9. Account Deletion (screen 14, Fase 2)

App Store submission blocker (Guideline 5.1.1(v)). Two screens.

**9a — Entry point**, reached from Profile. States plainly what will be deleted and what is retained: personal data is removed, but the points ledger is append-only and historical leaderboard entries remain under a frozen display name ([database-api-spec.md](../02-architecture/database-api-spec.md) §2.1b).

**9b — Explicit confirmation** (AC 4.17.2). A deliberate confirmation step, not a single tap. Destructive pill (`error` red). Must state that it is irreversible.

Copy here is a legal surface as much as a design one — it must agree with the Privacy Policy ([pre-launch-checklist.md](../04-quality-security/pre-launch-checklist.md) §1). Do not finalize the wording independently of that document.

---

## 10. Cross-cutting requirements

Applies to every screen above.

- **Forced dark.** No light-mode variant exists. Never use `.primary`/`.secondary`/system materials — they adapt to the system setting and break the brand decision (design-notes §0).
- **One lime per screen.** Exactly one element carries `accent` as the focal point. If two things are lime, one of them is wrong.
- **Dynamic Type.** System font (SF Pro) is used specifically so Dynamic Type keeps working. Hero numbers at the largest accessibility sizes are the stress case — check them.
- **Tap targets ≥ 52pt** for anything usable mid-run.
- **No shadows on black.** Depth comes from `surface`-vs-`background` contrast (design-notes §3).
- **Empty, loading, and error states are required**, not optional. A screen without them is not finished.
