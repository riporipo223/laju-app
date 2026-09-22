# ADR-0012: Periodic timer for auto-pause evaluation, not reactive-per-fix

**Date**: 2026-09-13 (Round 7 finding, tech-spec.md Auto-pause section)
**Status**: accepted
**Deciders**: Project lead, found via real on-device incident

## Context

The original auto-pause design evaluated "has the user stopped moving?" only reactively — inside the callback that fires when a new GPS fix arrives (`handle(_:)`). This has a structural blind spot: if the user stops moving and GPS fixes simply stop arriving (e.g. the `stationaryAnchor`/`distanceFilter` mechanism from ADR-0004 itself suppresses redundant fixes while stationary, or the device is indoors with degraded signal), the reactive check never runs at all — auto-pause could never fire, no matter how long the user has actually been stationary, because there is no next fix to trigger the evaluation.

## Decision

Auto-pause evaluation runs on a periodic timer, independent of whether a new GPS fix has arrived. The `stationaryAnchor` (ADR-0004) remains the single source of truth for "when was real movement last confirmed" — what changes is only *how that fact gets checked*: a recurring timer polls elapsed-time-since-anchor on a fixed interval, rather than waiting for the next `handle(_:)` callback to do the check inline.

## Alternatives Considered

### Alternative 1: Keep reactive-per-fix evaluation, rely on `distanceFilter`'s minimum update behavior to still deliver periodic fixes
- **Pros**: No separate timer to manage; one less moving part.
- **Cons**: `CLLocationManager`'s `distanceFilter` throttles *by distance*, not by time — it makes no guarantee of a minimum fix cadence while stationary. A user standing still, especially with degraded/indoor signal, can go arbitrarily long with zero fixes arriving, and zero fixes means zero chances for the reactive check to ever run.
- **Why not**: Directly falsified — this is the actual blind spot found, not a hypothetical.

### Alternative 2: Shorten `distanceFilter` or force periodic fixes via a lower `desiredAccuracy` to guarantee callback cadence
- **Pros**: Would keep the single-evaluation-path design (no separate timer).
- **Cons**: Defeats the purpose of `distanceFilter`-based throttling (T0.9's battery target, tech-spec.md §"Battery efficiency" row) — forcing fixes just to have something to hang the auto-pause check on wastes battery on data the app doesn't otherwise need.
- **Why not**: Trades away an already-validated battery efficiency result (T0.9's 3%/hour measurement) to work around a gap that a lightweight timer solves directly without touching GPS behavior at all.

## Consequences

### Positive
- Auto-pause now fires correctly even when GPS fixes fully stop arriving while stationary — closes the exact blind spot found on 2026-09-12 device re-verification (a second, related bug: Start→Pause(10s)→Resume(5s)→Stop scenario).
- `stationaryAnchor` stays the single source of truth for "last confirmed movement" — only the evaluation trigger changed, not the underlying signal, keeping ADR-0004's anchor design intact and unduplicated.
- Decouples auto-pause correctness from GPS fix delivery timing entirely, removing a whole class of future bugs tied to fix-cadence edge cases.

### Negative
- Introduces a recurring timer that must itself be correctly invalidated on pause/stop/background transitions — a second lifecycle to manage alongside the location manager's own, and a source of the separate false-trigger bug (`AutoPauseWatchdog.deferPauseForDegradedSignal()`) found and fixed later in the same area.

### Risks
- A periodic timer running during background execution has its own iOS lifecycle constraints (background task time limits) distinct from `CLLocationManager`'s own background delivery guarantees — must be verified not to get suspended independently of location updates.
