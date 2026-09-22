# ADR-0004: Stationary-anchor drift filter, not a simple distance threshold

**Date**: 2026-09-11 (found and fixed during T0.9 battery retest), hardened 2026-09-12 (T1.2b re-verify)
**Status**: accepted
**Deciders**: Project lead, found via real on-device incidents

## Context

Client-side GPS noise filtering (tech-spec.md §2.1b) exists to keep the locally-displayed distance/route sane — distinct from server-side anti-cheat (§2.4). Three independent, real on-device bugs were found while building this, each defeating a simpler filter than the one before it:

1. **Cold-fix jump (run pk=34, 2026-09-10)**: a single poor-accuracy fix produced an implied speed of 6459 km/h — no accuracy filter existed yet.
2. **Point-to-point jitter (run pk=38, 2026-09-11)**: after adding an accuracy/staleness/speed filter comparing each point only to the *previous accepted* point, a stationary phone still accumulated 33m from 5 individually-plausible-looking steps that were actually GPS noise oscillating around one spot.
3. **Stationary drift over time (run pk=41, 2026-09-11)**: a phone sitting still indoors for 60 minutes still accumulated 34.9m across three segments (14.32m, 14.32m, 6.25m), none of which individually tripped the accuracy/speed/jitter-floor filters — the reference point itself was drifting one small "plausible" step at a time.

Each fix before this one only compared a new point to the single most recent point — none of them could detect a slow, multi-step drift of the reference itself.

## Decision

Track a `stationaryAnchor` — the last point *confirmed* as real movement (not just the last accepted point). A new point within `stationaryRadiusMeters` (20m) of the anchor is recorded to the raw `gpsRoute` trail but does not count toward `distanceMeters` and does not move the anchor. The anchor only moves when a point lands outside that radius **and** its own `horizontalAccuracy` is ≤ `anchorAccuracyThresholdMeters` (10m) — the second condition was added after a fourth incident (2026-09-12) where an unconditionally-trusted poor first fix (15.11m accuracy) became a bad anchor, and a much more accurate fix 12s later (3.20m accuracy) read as 35m of "movement" that never happened. `distanceFilter=10m` on `CLLocationManager` itself throttles redundant updates as a complementary battery/noise measure, not a substitute for the anchor logic.

## Alternatives Considered

### Alternative 1: A simple fixed distance/speed threshold per point-pair
- **Pros**: Simple to implement and reason about.
- **Cons**: This is exactly what bugs #1 and #2 above were — and both were defeated by real GPS behavior (a single cold fix, and jitter oscillating within a fix's own accuracy radius).
- **Why not**: Directly falsified by on-device evidence, twice.

### Alternative 2: Compare each point only to the immediately preceding accepted point (no persistent anchor)
- **Pros**: Still simpler than a persistent anchor; catches large single jumps.
- **Cons**: This is what bug #3 defeated — a slowly-drifting reference point, where each individual step looks locally plausible even though the cumulative drift is not. No single point-pair comparison can detect "the reference itself walked away from truth."
- **Why not**: Structurally cannot solve the class of bug it was built to prevent — the anchor must persist across multiple points, not reset to whatever was last accepted.

### Alternative 3: Accept the first fix of a run unconditionally as the anchor
- **Pros**: Simple, no extra accuracy gate needed at anchor-establishment time.
- **Cons**: This is what the fourth incident defeated — a poor-quality first fix becomes a permanently bad reference point.
- **Why not**: The anchor's whole purpose is to be a trustworthy reference; an untrusted point should never become one, first-fix or not.

## Consequences

### Positive
- Distance/route noise is now judged against a genuinely-confirmed reference point, not merely the last accepted point — closes the entire class of "reference drift" bug, not just the specific incidents found.
- Every accepted point (including anchor-suppressed drift points) is still recorded to the raw `gpsRoute` trail — no data is discarded, only excluded from the `distanceMeters` accumulation. This matters for downstream consumers (see below).
- The same anchor state now also drives auto-pause (T1.11, product-spec §4.11) — a second consumer that reuses this exact mechanism rather than inventing a new stillness detector (tech-spec.md §2.1b).

### Negative
- `gpsRoute` is a **superset** of what counts toward `distanceMeters` (it includes anchor-suppressed drift points) — any function deriving distance from `gpsRoute` directly (splits, elevation, map rendering) must replicate the exact same anchor-acceptance logic or its numbers will not match `distanceMeters` (tech-spec.md §2.1b, Round 7 finding B7-1). This is a real coupling cost: the anchor algorithm is now a contract multiple features must stay in sync with, not just an internal `RunViewModel` detail.
- The anchor's own radius-check has only been directly exercised once in confirmed testing (a live device retest never produced a second point close enough to the anchor to evaluate) — most verification is strong practical evidence (zero phantom distance over an hour stationary) rather than a direct proof of the boundary condition. Documented as a known verification gap, not silently assumed solid.

### Risks
- The 20m stationary radius and 10m accuracy threshold are tuned from specific real incidents, not a formal model — a different GPS environment (e.g. dense urban canyon at a different severity than tested) could still find an edge case. Mitigation: both values are named constants, straightforward to retune if a new incident surfaces one.
