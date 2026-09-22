# ADR-0003: `CLLocationManager` directly, no third-party GPS library

**Date**: 2026-09-10 (Fase 0, decided alongside the Swift pivot)
**Status**: accepted
**Deciders**: Project lead

## Context

Background GPS tracking is the single most reliability-critical capability in the product. The pre-pivot React Native architecture used a third-party library (`react-native-background-geolocation`) as an abstraction over native location APIs (see ADR-0001). Going native removes the need for that abstraction, but a decision still had to be made about whether to use a native third-party wrapper around `CLLocationManager` or call it directly.

## Decision

Call `CLLocationManager` directly (`ios/Laju/Services/Location/LocationTrackingService.swift`) — no third-party GPS/location library, native or otherwise.

## Alternatives Considered

### Alternative 1: A native third-party location wrapper library
- **Pros**: Could offer convenience APIs (e.g. simplified permission flows, built-in filtering).
- **Cons**: Reintroduces the exact dependency-risk pattern the native pivot was meant to eliminate — an unvalidated layer between the app and the platform API in the most safety-critical path.
- **Why not**: No such library was found to offer a compelling enough advantage to justify reintroducing third-party risk here, especially once the filtering logic this project actually needed (accuracy/staleness/speed/stationary-anchor filtering, tech-spec.md §2.1b) turned out to require custom, product-specific tuning anyway (see ADR-0004) — a generic library's filtering wouldn't have fit without still writing custom logic on top.

## Consequences

### Positive
- Zero third-party dependency risk in the GPS pipeline — `LocationTrackingService` is the only code that talks to `CLLocationManager` (architecture.md §3's own layering rule), fully owned and auditable.
- Full control over `desiredAccuracy`, `distanceFilter`, `allowsBackgroundLocationUpdates`, and `pausesLocationUpdatesAutomatically` — all four were tuned directly against real on-device battery/accuracy findings (T0.9, tech-spec.md §4) rather than working around a library's defaults.
- Enabled building the four-layer client-side noise filter (ADR-0004) exactly to the product's own needs, discovered incrementally through real device bugs (cold-fix jump, GPS jitter, stationary drift) rather than adapting a generic library's filtering to fit those same problems after the fact.

### Negative
- All filtering/noise-handling logic had to be designed and hardened from scratch, incident by incident (three real on-device bugs found and fixed during Fase 0/1 — see ADR-0004) — a mature third-party library might have had some of this solved already, at the cost of not fitting the product's specific needs without customization anyway.
- No community-maintained bug fixes for `CLLocationManager` edge cases — any future platform-level GPS quirk is this project's own to discover and handle.

### Risks
- None significant — this is a well-trodden native API, and the project has already found and fixed its own real-world edge cases (documented in tech-spec.md §2.1b) rather than relying on unverified third-party claims of correctness.
