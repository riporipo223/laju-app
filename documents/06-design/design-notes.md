# Laju — Design System

Created 2026-09-14. First design-system document for this project — no
prior `design-notes.md` existed. `RunTrackingView.swift`'s own comments
("placeholder styling... system defaults... re-skin once a real design
system exists") are the thing this document supersedes; that screen and
every other screen built so far used plain SwiftUI system colors/materials
with no brand decision behind them.

## 0. How this was decided

Full extraction of 6 visual references + synthesis reasoning lives in
this session's own record (not duplicated here to avoid drift — the
decisions below are the *output* of that process, kept current here).
Two decisions worth restating because they constrain everything below:

1. **Laju is dark-native by brand identity, not by system-appearance
   following.** Every screen uses the same black/lime system regardless
   of the device's Light/Dark Mode setting. This is a deliberate pivot
   from the placeholder approach used while building T1.8-T1.14 (which
   used `.primary`/`.secondary`/system materials that adapt to the
   system setting) — those screens get restyled onto the fixed palette
   below, not left adaptive. Rationale: black+neon-lime contrast reads
   best in both direct sun and at night (the two real running
   conditions), and a single deliberate look is what makes this read as
   an authored product rather than a system-default shell.
2. **One neon accent, used everywhere, not one accent per screen.**
   Lime is the ONLY high-saturation "brand" color. Every other state
   (warning, error, locked/premium) gets its own hue explicitly reserved
   below — decided now, precisely so a later feature (anti-cheat flag,
   paywall) doesn't grab an arbitrary color under deadline pressure and
   quietly erode the one-accent discipline.

## 1. Color System

All values are fixed hex — this is a forced-dark system, so there is no
light-mode variant to define. SwiftUI `Color(hex:)` via a small helper
(see `LajuColor.swift`).

### Base

| Token | Hex | Use |
|---|---|---|
| `background` | `#000000` | Screen background, pure black — matches #6(bottom)'s literal black, not a near-black gray |
| `surface` | `#141414` | Card/panel fill — one step up from background so cards read as raised without a shadow |
| `surfaceRaised` | `#1E1E1E` | Nested surface (a card inside a card, e.g. a stat pill inside a summary card) |
| `hairline` | `#2A2A2A` | Dividers, inactive progress track, disabled borders |

### Brand accent

| Token | Hex | Use |
|---|---|---|
| `accent` (lime) | `#C6FF00` | THE brand color — hero numbers, primary pill buttons, route glow, progress fill, top-edge accent line on cards, streak-grid filled day. Nothing else is allowed to compete with this for visual weight on a screen. |
| `accentDim` | `#8FB800` | Lime at reduced perceived brightness for a *disabled* primary button (not a new hue, same accent turned down) |

### Text

| Token | Hex | Use |
|---|---|---|
| `textPrimary` | `#FFFFFF` | Secondary hero numbers (e.g. Pace, when Distance is the lime hero), headings, body |
| `textSecondary` | `#8A8A8E` | Uppercase tracked labels above stats, captions, timestamps |
| `textDisabled` | `#4A4A4C` | Disabled control labels |

### Semantic (reserved now, used as each feature ships)

Reserved so a future task never has to invent a color under pressure.
None of these are lime, and none of them are close enough on the color
wheel to be confused with it or with each other at a glance.

| Token | Hex | Use | First consumer |
|---|---|---|---|
| `warning` (amber) | `#FF9F1C` | Run flagged / pending anti-cheat verification ("sedang diverifikasi", user-flow.md §2.2) | Fase 2, Run Summary's flagged state |
| `error` (red) | `#FF453A` | Destructive actions (Finish/discard confirmation), failed states | Already needed now — replaces the current placeholder `.red` tint on Finish |
| `premium` (violet) | `#B983FF` | Locked/premium CTA, paywall badges — deliberately a hue family (violet) with no other current use, so "locked" never gets confused with "warning" or "earned" | Fase 2 monetization |
| `success` | *(reuses `accent`)* | Level-up / achievement — deliberately NOT a separate green; leveling up IS the core reward moment and should read as "more lime", not a new color | Already needed (Run Summary level-up, confetti) |

## 2. Typography

System font (SF Pro) — no bundled custom font, so Dynamic Type keeps
working automatically. Distinctiveness comes from weight/design choices
most apps don't bother making, not from a custom typeface.

| Role | Spec | Example |
|---|---|---|
| Hero number | `.system(size: 56, weight: .heavy, design: .rounded)`, `.monospacedDigit()` | Live Distance/Pace, Run Summary headline stat, streak day count |
| Section number | `.system(size: 28, weight: .bold, design: .rounded)`, `.monospacedDigit()` | Secondary stat card values |
| Label (tracked) | `.system(size: 12, weight: .semibold)`, `.tracking(1.2)`, uppercase, `textSecondary` | "DISTANCE", "AVG PACE" — above a number, never beside it |
| Heading | `.system(size: 22, weight: .bold, design: .rounded)` | Screen titles, card titles ("Afternoon Power Run") |
| Body | `.system(size: 15, weight: .regular)` | Supporting copy |

`design: .rounded` on numbers/headings only — it's the one deliberate,
consistent typographic signature that costs nothing (no font license)
but reads distinctly from the system-default look used everywhere else.

## 3. Components

- **Primary pill button** — full `accent` fill, `background`-black text,
  `Capsule()`, large tap target (`.controlSize(.large)`, min 52pt tall).
  Used for the one primary action per screen (Start, Continue, Run).
- **Secondary pill button** — `surface` fill, white text, `Capsule()`,
  a 2pt `accent` line across the TOP edge only (not a full border —
  #6(bottom)'s signature detail). Used for Pause/Resume, secondary
  onboarding actions.
- **Destructive pill button** — `error` fill, white text, `Capsule()`.
  Used for Finish/discard confirmations only.
- **Stat card** — `surface` fill, `RoundedRectangle(cornerRadius: 20)`,
  NO shadow (shadows don't read on black — depth comes from the
  surface-vs-background contrast alone), 2pt `accent` line across the
  top edge.
- **Streak grid** — 7-column heatmap, filled `accent` circle for a
  qualifying day, hollow `hairline`-stroke circle for a miss, today gets
  a thin `accent` ring even if not yet filled.
- **Badge/chip** — `Capsule()`, `accent`-stroked + `accent` text on
  transparent fill for "earned", `hairline`-stroked + `textDisabled`
  text for "not yet earned", `premium`-stroked for a locked/paid badge.
- **Route line (map)** — `accent` stroke with a soft outer glow
  (`.shadow(color: .accent.opacity(0.6), radius: 6)` on the polyline
  layer) instead of the current plain `.systemBlue` line.

## 4. Motion Principles

Purposeful, not omnipresent — per-moment, not a global "everything
fades and slides" default.

**Gets deliberate, noticeable motion:**
- Level-up reveal (Run Summary) — the number/badge should feel earned
- Streak grid filling in (a cascading fill when the grid first appears,
  not on every re-render)
- Run Summary reveal itself — the whole sheet's entrance
- Confetti burst on Finish (see below)
- Onboarding screen transitions (first impression)

**Deliberately NOT animated (or animated minimally):**
- Live stat updates during an active run (Time ticking, Distance
  incrementing) — must read as stable/trustworthy while the user is
  mid-run, not distracting
- Run History list scroll/appearance — plain list semantics
- GPS status banner changes — a flicker here would read as an error,
  not a feature

**Confetti spec (Run Summary, on Finish):** particles in `accent` lime
+ white only (not default multicolor) — 1.2s burst, falls and fades,
must not obscure the stat numbers (confined to the upper portion of the
sheet, or behind the stats in z-order). Never loops.

## 5. Screen Application Map

| Screen | Primary reference | Status |
|---|---|---|
| Onboarding (new) | #4 structure (full-bleed → headline → SSO pills → email → sign-in link), recolored to black+lime | Building now |
| Run Tracking | #6(bottom) — base identity screen | Restyle next |
| Run Summary | #6(bottom) stat grid + confetti (accent-colored) | Restyle after |
| Run History | #6(bottom) card system, dark list rows | Restyle after |
| Profile/Level (new) | #6(top)'s streak-grid heatmap, re-colored | Build after |
| Leaderboard (Global built in Fase 2, T2.20; Local deferred to v1.1) / Circle (Fase 4, not built) | #5's podium + per-rank progress bars | Reference only, not built yet |
