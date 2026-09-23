# Laju — Screen Inventory

Created 2026-09-17. The complete list of screens this product needs, with build status and visual dependencies. Companion to [design-notes.md](./design-notes.md) (the design system itself) and [wireframe-spec.md](./wireframe-spec.md) (per-screen element breakdown).

**Scope boundary.** This inventory covers only screens implied by [product-spec.md](../01-product/product-spec.md) §4 (features 4.1-4.18), which is the reconciled MVP scope. [user-flow.md](../01-product/user-flow.md) describes additional screens — Circle, Social Feed, Paywall, Advanced Statistics, Cloud Backup — but that document is explicitly labelled *"draft standalone, belum diintegrasikan"*, and those features sit in Fase 4 backlog or are undecided. They are listed in §4 below as **out of scope**, so it is clear they were considered and excluded rather than forgotten. Do not wireframe them.

---

## 1. Status legend

| Status | Meaning |
|---|---|
| **Built — restyled** | Exists in code and already uses the design system (LajuColor/LajuTypography) |
| **Built — placeholder** | Exists in code but still on system defaults; needs restyle onto the black+lime palette |
| **Not built** | No code yet. Owning task exists; design can run ahead of it |
| **State only** | Not a separate screen — a state of a screen already listed |

---

## 2. Screens — Fase 1 (core loop, offline)

| # | Screen | Entry point | File(s) | Owning task | Status |
|---|---|---|---|---|---|
| 1 | Onboarding — Welcome | First launch (step 1) | `Views/Onboarding/OnboardingWelcomeStep.swift` | — (design-system pass) | **Built — restyled** |
| 2 | Onboarding — Core Loop explainer | Step 2 | `OnboardingCoreLoopStep.swift` | — | **Built — restyled** |
| 3 | Onboarding — Sign in | Step 3 | `OnboardingSignInStep.swift` | T2.3 (real auth) | **Built — restyled**, but non-functional — see §5 |
| 4 | Onboarding — Location permission | Step 4 | `OnboardingPermissionStep.swift` | T1.15 | **Built — restyled** |
| 5 | Run Tracking | **Track** tab (default) | `RunTrackingView.swift`, `RunMapView.swift`, `RunTrackingOverlayButtons.swift` | T1.2b, T1.8, T1.11, T2.0a | **Built — restyled** |
| 6 | Run Summary | Sheet on Stop | `RunSummaryView.swift`, `DesignSystem/ConfettiBurstView.swift` | T1.2, T1.3, T1.9, T1.10, T1.12 | **Built — restyled** |
| 7 | Run History | Overlay button on the Track tab (still a push, not a tab) | `RunHistoryView.swift` | T1.5 | **Built — restyled** |
| 8 | Profile / Level | **You** tab | `ProfileView.swift` | T1.6, T2.0a | **Built — restyled** |

**Onboarding step order note:** the code runs welcome → coreLoop → **signIn → permission** (`OnboardingContainerView.swift:8`). This is a deliberate 2026-09-14 sequencing decision that differs from [user-flow.md](../01-product/user-flow.md) §2.1, which still describes permission *before* sign-up. The code comment flags that user-flow.md should be updated if this order is kept — **that sync has not happened**, and it is listed as an open item in [documents/README.md](../README.md) §3.

**All eight Fase-1 screens are restyled onto the black+lime system** (verified 2026-09-17 against the source: each carries an explicit "Restyled 2026-09-14" comment, uses `LajuColor`/`LajuTypography` throughout, and contains zero `.primary`/`.secondary` system-adaptive colors). An earlier draft of this file wrongly marked screens 5-7 as placeholder; that was corrected the same day. The consequence matters: **there is no restyle backlog.** Remaining design work is Fase 2/3 screens and undesigned states, not rework of what exists — see §6.

### States that need their own design, on screens already listed

| # | State | Belongs to | Owning task | Status |
|---|---|---|---|---|
| 5a | GPS signal degraded / searching | Run Tracking | T1.8 | **State only** — banner exists, unstyled |
| 5b | Auto-paused (visually distinct from manual pause) | Run Tracking | T1.11 | **State only** — required by AC 4.11.2 |
| 5c | Location permission: While-Using warning | Run Tracking | T1.15 | **State only** — `LocationPermissionBanner.swift` |
| 5d | Location permission: Denied | Run Tracking | T1.15 | **State only** |
| 6a | Level-up moment | Run Summary | T1.3 | **State only** — needs the "earned" motion treatment |
| 6b | Streak-reminder permission prompt | Run Summary | T1.16 | **State only** — contextual, gated on `streakDays >= 1` |
| 6c | Zero-GPS-points empty map | Run Summary + Run History | T1.9 | **State only** — required by AC 4.9.3 |
| 7a | Empty history (no runs yet) | Run History | T1.5 | **State only** — device-verified as distinct |
| 8a | Crash-recovery resume prompt | App launch | T1.14 | **State only** — resume vs save-as-finished |

---

## 3. Screens — Fase 2 and 3 (not built)

Design can and should run ahead of these — none require the code to exist first.

| # | Screen | Owning task | Phase | Notes |
|---|---|---|---|---|
| 9 | Sign Up / Sign In (functional) | T2.3 | 2 | Replaces screen 4's placeholder. **Two buttons since 2026-09-21: Sign in with Apple + Sign in with Google** (Apple stays — Guideline 4.8; see [pre-launch-checklist.md](../04-quality-security/pre-launch-checklist.md) §5). Google uses the design system's secondary button, not Google's default pill |
| 10 | ~~Profile completion — region picker~~ **REMOVED 2026-09-22** | ~~T2.4, T3.1~~ (rework: Task C) | — | ~~Blocks first run submit (AC 4.1.2). Three-level cascade: kecamatan → kabupaten-kota → provinsi. Region no longer feeds any v1 screen (Local Leaderboard deferred, 2026-09-21) — kept, and still mandatory, because data is collected now for later (D1 final, 2026-09-21, product-spec.md §4.1)~~ **D1 reversed 2026-09-22: region removed entirely from onboarding and the schema. This screen's region portion is deleted, not redesigned; the picker is never built. Replacement gate for leaderboard access is location permission (product-spec.md §4.5 AC5), which needs no new screen — it reuses the existing permission banner pattern (screen-level design TBD in Task C)** |
| 11 | Global Leaderboard | T2.20 | 2 | Top N + own rank (AC 4.5.1). **The only leaderboard in v1.** League view state ("liga sendiri" vs "semua liga", Freemium/Premium, AC 4.5.4; "tier" = Season League, tech-spec.md §2.5) is a future state — Premium tier not built, not designed yet. Showing the user's *own* league (T3.7a) can live on Season Info (13) |
| 12 | ~~Local Leaderboard + scope filter~~ **CANCELLED PERMANENTLY 2026-09-22** (was "DEFERRED to v1.1 / Fase 4") | T3.5 *(phase-4-backlog.md)* | — | Cut from MVP v1 (2026-09-21, product decision — needs high user density). Kept as reference: three scopes, plus the "belum cukup data" state (AC 4.6.2). No design work needed now |
| 13 | Season Info + countdown | T3.9 | 3 | Time remaining (AC 4.7.2), final rank history (AC 4.7.3) |
| 14 | Account Deletion flow | T2.22 | 2 | Two screens: entry + explicit confirmation (AC 4.17.1-4.17.2). App Store submission blocker |
| 12a | ~~Leaderboard — insufficient data~~ **CANCELLED PERMANENTLY 2026-09-22** with screen 12 (was "DEFERRED") | T3.3, T3.5 *(phase-4-backlog.md)* | — | **State only.** Belongs to the Local Leaderboard; not needed in v1 (Global's `insufficient_data` is always `false`) |
| 6d | Run Summary — flagged / "sedang diverifikasi" | T2.14b | 2 | **State only** — uses `warning` amber, the token reserved for exactly this |
| 6e | Run Summary — resolution changed after the fact | T2.14b, T2.14d | 2 | **State only** — points may go *down*; this is expected, not an error |

---

## 4. Explicitly out of scope — do not wireframe

From [user-flow.md](../01-product/user-flow.md), which is an unreconciled draft: Circle / Clan (T4.1), Circle War (T4.2), Social Feed and post composer (T4.15-T4.16), Paywall / upgrade flow (T4.4-T4.7), Advanced Statistics (T4.5), Cloud Backup & Restore (not scheduled), Apple Health sync (T4.13), alternate app icon picker (T4.7), **Laju Branded Events — Social tab → Events sub-tab, card feed (T4.9, added 2026-09-23, see product-spec.md §4.21)**.

Listed so the exclusion is a recorded decision. If any of these is promoted into scope, it gets a row in §3 and a section in `wireframe-spec.md` at that time — not before.

---

## 5. Visual dependency graph

Which screens must stay consistent with which. **Design in this order** — a screen should not be finalized before the screens it depends on.

```
Run Tracking (5)  ──────►  Run Summary (6)  ──────►  Run History (7)
   │  base identity screen     inherits stat-card         inherits card
   │  (#6-bottom reference)    grid + hero number         system + route
   │                                                       thumbnail
   │                                 │
   ▼                                 ▼
Profile / Level (8)  ◄────────  level-up treatment
   │  streak grid                shared with 6a
   │
   ▼
Leaderboard global (11)  ─ ─ ─ ►  [Leaderboard local (12) — CANCELLED PERMANENTLY 2026-09-22]
   │  row + rank + own-rank          (would add scope filter chips
   │  pinned row                     + insufficient-data state; not in v1)
   ▼
Season Info (13)
   reuses leaderboard row for historical final rank
```

Reading the graph:

- **Run Tracking (5) is the base identity screen.** Everything downstream inherits its hero-number treatment and stat-card system. Restyle it first; it is the reference the others are judged against.
- **Run Summary (6) is the highest-stakes screen in the product.** It is where the core reward moment lands (product-spec §1's whole hypothesis), and it carries the most states — level-up, confetti, flagged, streak prompt, empty map. Budget the most design time here.
- **Run History (7) and Profile (8) are card-system consumers.** Once 5 and 6 are settled, these are largely composition.
- **Leaderboard (11) introduces one genuinely new pattern** — a dense repeating row with rank, name, points, and a pinned "your rank" row. Nothing earlier in the product has this. Design 11 now; 12 (11 plus filter chips) is CANCELLED PERMANENTLY (2026-09-22) with the Local Leaderboard — never to be designed.
- **Season Info (13) reuses the leaderboard row** for historical rank, so it should come last.

### Cross-cutting: navigation shell — **decided and built 2026-09-17**

`RootTabView` is the app root, with a `TabView` carrying two tabs:

| Tab | Content | Symbol |
|---|---|---|
| **Track** | `RunTrackingView` (screen 5) | `figure.run` |
| **You** | `ProfileView` (screen 8) | `person.fill` |

Owned by task **T2.0a**, placed first in Fase 2 because screens 11, 12 and 13 were otherwise unreachable-by-construction — each built a screen with no entry point, and no task owned creating one.

What this settles for design work:

- **Only tabs with real content are shown.** No empty or disabled placeholder tabs. A Social tab arrives with T2.20's leaderboard; a Circle tab only if the Fase-4 Circle feature is promoted into scope, which is undecided. Do not wireframe a tab that does not exist yet.
- **Adding a tab is cheap** — one `LajuTab` enum case plus one `tabItem` block — so screens 11-13 can be designed now without knowing exactly where their tab will sit.
- **Run History is still an overlay push from Track**, not a tab. Profile shows only the 5 most recent runs, so that overlay remains the only route to the full list.
- **Profile's floating overlay button on the Track screen was removed** — it was a second route to what is now a tab.
- The tab bar inherits forced-dark from `LajuApp`'s window-level `.preferredColorScheme(.dark)`.

One open verification, not a design question: on the iOS 26.3 simulator the two tab icons also render in the status-bar area on the You tab. Only that runtime is installed locally, so it is unresolved whether this is iOS 26-specific or a real layout bug on the iOS 16 deployment target. Tracked in [deferred-manual-tests.md](../04-quality-security/deferred-manual-tests.md).

---

## 6. Current design priority

Derived from status above plus the task sequence in [tasks/README.md](../03-development/tasks/README.md). Kept in sync with [documents/README.md](../README.md), which is the single place to look for "what do I work on now".

**Every Fase-1 screen is already built and restyled.** So the work is not rework — it is the screens that do not exist yet, and the states nobody has designed.

1. **Global Leaderboard (11)** — the highest-value thing you can design right now. It is the one genuinely new pattern in the product (a dense repeating row with a pinned own-rank row), nothing existing gives it to you for free, and T2.20 is far enough out that design will not be rushed by implementation.
2. **Region picker (10)** — three-level cascade over thousands of Indonesian kecamatan. Fiddly enough that solving it on paper before T2.4/T3.1 codes it will save real time. Region stays mandatory (D1 final, 2026-09-21); the "why we ask" copy must be honest that it is for regional rankings coming later (wireframe-spec §8 item 4).
3. **Undesigned states on screens that exist** — these are cheap and they are what actually ships broken if skipped:
   - 6d — Run Summary flagged / "sedang diverifikasi" (Fase 2). The `warning` amber token was reserved for exactly this and has never been used.
   - 6e — Run Summary after a resolution changes points, possibly **downward**.
   - 5b — auto-paused, which must read as visually distinct from manual pause (AC 4.11.2).
   - 6c / 7a — the empty states. (12a, insufficient-data, is deferred with the Local Leaderboard, 2026-09-21.)
4. **Account Deletion (14)** — two screens, App Store submission blocker. Copy is a legal surface; coordinate with the Privacy Policy rather than finalizing wording alone.
5. **Season Info (13)** — last, because it reuses the leaderboard row from item 1.

**Not on this list, deliberately:** restyling screens 1-8. They are done. If something about them feels wrong in use, that is a refinement decision worth making, but it is not outstanding work — and the navigation-shell question (§5) is the one thing that could genuinely force changes to them.
