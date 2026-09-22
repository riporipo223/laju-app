# ADR-0008: Server-side anti-cheat as a separate architecture from client-side sanity filtering

**Date**: 2026-09-10, hardened through Fase 1 (tech-spec.md §2.1b/§2.4)
**Status**: accepted
**Deciders**: Project lead

## Context

Two different problems that both operate on GPS/pace data risked being conflated: (1) client-side GPS *noise* — cold fixes, jitter, stationary drift — which just needs to keep the locally-displayed numbers sane for an honest user (ADR-0004), and (2) server-side *cheating* — deliberately fabricated or manipulated pace/GPS data submitted to gain unfair leaderboard position, which needs to be authoritative and impossible for the client to bypass, since the client cannot be trusted (tech-spec.md §2.4: "server adalah source of truth").

## Decision

Keep two structurally separate systems with different thresholds tuned for different purposes:
- **Client-side** (`LocationTrackingService`/`RunViewModel`, tech-spec.md §2.1b): accuracy/staleness/speed filters (e.g. `maxPlausibleSpeedMetersPerSecond=12`, ~43 km/h) and the stationary-anchor drift filter (ADR-0004) — generous, display-quality thresholds, never sent to or trusted by the server.
- **Server-side** (`backend/lib`, tech-spec.md §2.4): pace-cap (<3:00/km sustained >1km), GPS speed-jump (>25 km/h sustained >3 samples), distance/duration sanity, and elevation-anomaly checks feeding a count-based `excluded_pct`, plus a `trust_score` that persists across runs and applies a `trust_multiplier` to future point awards. These checks are tighter and explicitly framed as anti-cheat, not display cleanup — the two systems are never conflated into one filter with one threshold.

## Alternatives Considered

### Alternative 1: One shared filter, reused for both client display and server anti-cheat
- **Pros**: Less code, one set of thresholds to maintain.
- **Cons**: The two use cases have genuinely different tolerances — client-side filtering must be generous enough to not visibly glitch an honest user's live display (a false-positive there is immediately visible and annoying), while server-side anti-cheat must be strict enough to actually deter/catch manipulation (a false-negative there corrupts the leaderboard). Tuning one threshold to satisfy both simultaneously is not possible without compromising one goal for the other.
- **Why not**: The two systems were kept deliberately un-merged specifically so each could be tuned against its own correct failure mode, per tech-spec.md §2.1b's own explicit note: "dua mekanisme ini sengaja gak digabung, threshold-nya beda tujuan."

### Alternative 2: Trust the client's own filtering as sufficient anti-cheat, skip a separate server-side system
- **Pros**: Less backend work.
- **Cons**: A client-side filter can always be bypassed by a modified client, a jailbroken device, or GPS-spoofing tooling that feeds fabricated coordinates directly into `CLLocationManager`'s data path before the app ever sees them — the client has no way to verify its own inputs are genuine.
- **Why not**: Violates the foundational principle tech-spec.md §2.4 states explicitly — the server must be the source of truth precisely because the client cannot be trusted, and Fase 2's hard dependency (development-plan.md) blocks the public leaderboard specifically until server-side anti-cheat is verified working.

## Consequences

### Positive
- Client-side display quality and server-side fairness can each be tuned independently against real incident data without one goal fighting the other (e.g. the client's 12 m/s speed ceiling is deliberately looser than any anti-cheat threshold — it only protects local display from GPS noise).
- `excluded_pct` (server-side) is explicitly documented as count-based (excluded segments / total segments), not distance-based — a deliberate metric choice independent of the client's own distance-accumulation logic, so the two systems don't even share a unit of measurement, reinforcing the separation.
- A real 24km motor-vehicle calibration run (pk=81, 2026-09-13) confirmed the server-side pace-cap and GPS-speed-jump thresholds would correctly exclude that entire non-running activity if anti-cheat were active — validated against real data, not just designed on paper.

### Negative
- Two separate systems means two separate places to maintain and reason about when tuning GPS-related behavior — a contributor must know which system a given threshold belongs to before changing it.
- A real blind spot was found via the same calibration data (not yet fixed, deliberately deferred to Fase 2 design): the server-side GPS-speed-jump rule requires ">3 samples sustained," so a single large-gap "teleport" segment (e.g. 190s/2273m, still under the per-segment speed ceiling) would not trigger it today — documented as a known gap for a future duration/gap-aware check, not silently missed.

### Risks
- `trust_score`/`trust_multiplier` persist across runs by design (a graduated consequence, not a binary ban) — but `trust_score` is also explicitly evadable by delete-then-re-register (see database-api-spec.md §2.1b point 7, and the security review) since it lives on the `User` row, not on a more persistent identity signal. Documented as an accepted v1 risk, not solved by this architecture.
