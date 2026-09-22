# ADR-0009: Minimum-distance gate on the point formula (anti-farming)

**Date**: 2026-09-13 — found and fixed via real on-device evidence (tech-spec.md §2.2)
**Status**: accepted
**Deciders**: Project lead, found via real on-device incident

## Context

The point formula's `streak_bonus` is additive (`raw_points = base_points + streak_bonus`), not multiplicative against distance. Before this decision, there was no gate preventing `distance_km = 0` (and therefore `base_points = 0`) from still producing a full `streak_bonus`. This was proven exploitable on-device: two runs with `distanceMeters = 0.0` (tap Start, then immediately Stop, no movement) produced 6.0 and 8.0 points — exactly `min(streak_days, 7) * STREAK_BONUS_PER_DAY` for `streak_days` 3 and 4 respectively, confirmed against real streak history on the device. A user could spam Start/Stop with zero effort and still farm points off an existing streak.

## Decision

Gate `raw_points` to `0` entirely (both `base_points` **and** `streak_bonus`) whenever `distance_km < MIN_DISTANCE_KM_FOR_POINTS`. Set `MIN_DISTANCE_KM_FOR_POINTS = 0.1km` (100m) — deliberately 5× the stationary-anchor radius (ADR-0004's 20m), so the gate sits well above the GPS noise floor and cannot be satisfied by drift alone, while still being trivial for any genuine movement. Additionally, a day where the user's run doesn't clear this gate does **not** count as a qualifying day for the *next* day's `streak_days` calculation — otherwise a user could keep a streak alive indefinitely with zero-effort Start/Stop taps, banking it for a real run later.

## Alternatives Considered

### Alternative 1: Gate only `base_points`, leave `streak_bonus` additive and ungated
- **Pros**: Smaller change — this was the pre-fix state.
- **Cons**: This is the exact exploit found on-device — `streak_bonus` alone survived a zero-distance run entirely.
- **Why not**: Directly falsified by real evidence (6.0/8.0 points from two 0m runs).

### Alternative 2: Make `streak_bonus` multiplicative against `distance_km` instead of additive
- **Pros**: Would naturally zero out at `distance_km = 0` without needing an explicit gate.
- **Cons**: Changes the formula's fundamental shape (streak bonus currently rewards consistency as a flat per-day amount, capped at 7 days, independent of how far that day's run was) — a bigger, more consequential formula redesign than the bug warranted, and would need its own re-validation against the fixture file and real running data.
- **Why not**: The additive shape itself isn't the problem — the missing floor is. A minimum-distance gate fixes the actual exploit without touching the formula's core reward shape.

### Alternative 3: Set the minimum distance threshold much higher (e.g. 1km, "a real run")
- **Pros**: A stronger signal of genuine effort.
- **Cons**: The gate's purpose is explicitly anti-grinding, not a fitness bar — tech-spec.md §2.2 states directly: "100m = 5x radius anchor, margin lebar tapi tetap trivial buat gerakan nyata sekecil apapun (bukan bar 'olahraga', cuma bar anti-grinding)." A 1km bar would reject genuinely short intentional runs/walks that aren't farming attempts.
- **Why not**: Conflates two different goals (excluding zero-effort exploitation vs. requiring a minimum "real workout" length) that don't need to be the same number.

## Consequences

### Positive
- Closes the exact exploit found on-device — a `distance_km = 0` run now always produces `raw_points = 0`, regardless of streak.
- The streak-qualification consequence (a non-qualifying day doesn't count toward tomorrow's streak) closes a second-order version of the same exploit — a user can no longer keep a streak "alive" indefinitely via empty taps, banking it for a real run later.
- 100m is deliberately margin-wide relative to the GPS noise floor (ADR-0004's 20m anchor radius) — the gate cannot be accidentally or maliciously satisfied by GPS drift alone, only by genuine movement.

### Negative
- Any run genuinely shorter than 100m (a real but very short walk/jog) now earns zero points, including zero streak bonus — an intentional trade-off (anti-grinding bar, not a fitness bar), but still a real behavior change for that edge case.

### Risks
- `MIN_DISTANCE_KM_FOR_POINTS` (100m) and `STREAK_BONUS_PER_DAY` (2 points/day, cap 7 days) are both explicitly starting values pending tuning against real usage data (same status as the pace-multiplier table, tech-spec.md §2.3) — not yet validated at scale.
