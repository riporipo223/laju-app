# Laju — Prototyping Reference

Created 2026-09-17. Every interaction and animation decision already made on this project, in one place, so none of them get forgotten or silently re-decided during prototyping.

**Nothing here is new.** Each entry is extracted from [design-notes.md](./design-notes.md), from acceptance criteria in [product-spec.md](../01-product/product-spec.md) §4, or from behavior already implemented in code. Where a decision genuinely has not been made, it is listed in §7 as an open question rather than filled in with a guess.

---

## 1. Motion principles (design-notes §4)

The governing rule: **purposeful, not omnipresent.** Motion is decided per moment, not applied as a global "everything fades and slides" default. A prototype that animates everything is not following this system.

### Gets deliberate, noticeable motion

| Moment | Why it earns motion |
|---|---|
| Level-up reveal (Run Summary) | The number/badge should *feel earned* — this is the core reward |
| Streak grid filling in | A cascading fill **when the grid first appears**, not on every re-render |
| Run Summary reveal | The whole sheet's entrance — the transition into the reward moment |
| Confetti burst on Finish | See §2 |
| Onboarding screen transitions | First impression |

### Deliberately NOT animated

| Moment | Why it must stay still |
|---|---|
| Live stat updates during a run (time ticking, distance incrementing) | Must read as **stable and trustworthy** while the user is mid-run. Animation here reads as instability in a number the user is making decisions on |
| Run History list scroll / appearance | Plain list semantics. Nothing to celebrate here |
| GPS status banner changes | A flicker here reads as an **error**, not a feature |

That second table matters as much as the first. "Where we deliberately did not animate" is a real decision and is the one most likely to be lost when prototyping, because adding motion always feels like adding polish.

---

## 2. Confetti burst — full spec

Fires on Finish, on Run Summary. Implemented: `ios/Laju/DesignSystem/ConfettiBurstView.swift`.

| Property | Decision |
|---|---|
| **Colors** | `accent` lime + white **only** — explicitly not default multicolor |
| **Duration** | 1.2s |
| **Behavior** | Burst, then falls and fades |
| **Looping** | **Never loops.** One burst per Finish |
| **Z-order / placement** | Must **not obscure the stat numbers** — confined to the upper portion of the sheet, or placed behind the stats in z-order |

The color restriction is the load-bearing decision: default multicolor confetti would be the single biggest violation of the one-accent discipline in the whole product, on the most emotionally important screen.

---

## 3. Onboarding transitions

Four steps, in this order: **Welcome → Core Loop explainer → Sign in → Location permission** (`OnboardingContainerView.swift:8`).

That order is a deliberate 2026-09-14 decision and it **differs from [user-flow.md](../01-product/user-flow.md) §2.1**, which still describes permission before sign-up. The code is authoritative; user-flow.md has not been updated to match, and that sync is tracked as an open item in [documents/README.md](../README.md) §3. Prototype against the code order.

- Screen transitions **get deliberate motion** (design-notes §4) — this is the first impression.
- The location permission step explains **why** before the system prompt appears. This is a sequencing decision inherited from the reference structure rather than a stated acceptance criterion — product-spec §4.15's ACs cover the three authorization states and the Settings deep link, not pre-prompt framing. (The explicit "contextual framing" requirement, AC 4.16.1, applies to *notification* permission, not location.) The system prompt itself is not stylable, so the preceding screen carries the entire persuasive burden — prototype the handoff into the system dialog, not just the screen.
- Onboarding completes once, gated by `hasCompletedOnboarding` in `@AppStorage`. There is no re-entry path — prototypes should not assume the user can go back through it.

---

## 4. Run tracking interactions

| Interaction | Decided behavior |
|---|---|
| **Start** | Single primary pill tap. Begins tracking immediately |
| **Pause / Resume** | Secondary pill. On pause, GPS updates **stop entirely** — not "keep receiving and ignore" (T1.2b). The gap is a real time gap |
| **Stop** | Requires confirmation (user-flow §2.2: "Selesai lari?"). Destructive pill |
| **Auto-pause** | Fires after sustained no-movement, evaluated on a **periodic timer**, not on GPS-fix arrival (ADR-0012). Must look **visibly different from manual pause** (AC 4.11.2) |
| **Resume from auto-pause** | Behaves exactly like resume from manual pause. **Auto-resume is explicitly out of scope** (AC 4.11.3) — the user always resumes deliberately |
| **Map position** | Custom annotation fed from the ViewModel's own state. Never `showsUserLocation`, never `UserAnnotation` (ADR-0011) |
| **Map heading cone** | Reuses `CLLocation.course`. Absent when the fix has no valid course — the prototype needs a no-heading state |

---

## 5. Timing constraints that constrain prototypes

These come from acceptance criteria and are not negotiable in a prototype that claims to represent the product.

| Constraint | Source | Prototype implication |
|---|---|---|
| Point estimate visible **< 2s** after Stop | AC 4.3.1 | The reward moment cannot wait on a network call. Prototype it as instant |
| Audio cue fires **once per km**, containing distance **and** pace | AC 4.13.1 | Two pieces of content, one event |
| Leaderboard data up to **15 min stale** | AC 4.5.2 | Never prototype the leaderboard as live-updating |
| Auto-pause threshold: sustained no-movement | AC 4.11.1 | Default 60s (`AutoPauseThreshold.seconds`) |
| Flagged run resolution arrives **later**, asynchronously | tech-spec §2.4.1 | Points can change after the user has already seen them, including downward |

---

## 6. Component behavior already fixed (design-notes §3)

| Component | Fixed behavior |
|---|---|
| **Primary pill** | Full `accent` fill, black text, `Capsule()`, min 52pt tall |
| **Secondary pill** | `surface` fill, white text, 2pt `accent` line across the **top edge only** — not a full border |
| **Destructive pill** | `error` red fill, white text. Finish/discard confirmations only |
| **Stat card** | `surface` fill, 20pt corner radius, **no shadow**, 2pt `accent` top-edge line |
| **Streak grid** | Filled `accent` circle = qualifying day; hollow `hairline` circle = miss; today gets a thin `accent` ring even when unfilled |
| **Badge / chip** | `accent`-stroked = earned; `hairline`-stroked + `textDisabled` = not yet earned; `premium` violet-stroked = locked/paid |
| **Route line** | `accent` stroke with soft outer glow, not a plain system-blue line |

The "no shadow" rule is easy to lose in a prototyping tool that offers shadows by default: shadows do not read on pure black, and depth here comes from `surface`-vs-`background` contrast alone.

---

## 7. Open — not yet decided

Listed explicitly so a prototype does not accidentally become the decision by default.

1. ~~**Navigation shell.**~~ **Decided and built 2026-09-17** (task T2.0a): `RootTabView` is the app root with two tabs — Track (`RunTrackingView`) and You (`ProfileView`). Only tabs with real content are shown; a third arrives with T2.20's leaderboard. Prototype against a two-tab bar, and note that Run History is still an overlay push from Track rather than a tab. See [screen-inventory.md](./screen-inventory.md) §5.
2. **Level-up motion specifics.** Design-notes says it "should feel earned" and gets deliberate motion, but duration, easing, and whether it is a number count-up or a badge reveal are not specified.
3. **Run Summary sheet entrance.** Listed as getting deliberate motion; the actual transition (sheet slide, scale, fade) is unspecified.
4. **Streak grid cascade timing.** "Cascading fill when the grid first appears" — per-cell delay and total duration unspecified.
5. **Podium treatment for leaderboard ranks 1-3.** Design-notes §5 references a podium as a visual reference, but whether Laju actually uses one is undecided. See the caution in [wireframe-spec.md](./wireframe-spec.md) §5.

Items 2-4 are genuinely design decisions and are **yours to make during prototyping** — they are listed here because they are unspecified, not because they are blocked. Item 1 is different: it is a product/navigation decision that affects task scope, so it should be settled explicitly rather than implied by a prototype.
