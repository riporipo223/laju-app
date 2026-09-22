# ADR-0011: MapKit over Mapbox for live/static route maps

**Date**: 2026-09-12 (locked, superseding an earlier Open Question — tech-spec.md §1)
**Status**: accepted
**Deciders**: Project lead

## Context

Live map during tracking and static route maps on Run Summary/History (product-spec.md §4.8-4.9) were originally a Fase-4 Non-Goal specifically because Mapbox (the originally-assumed Maps SDK) has per-request billing, and route-map visualization wasn't judged worth that cost pre-validation of the core loop (lean-canvas.md §7's original cost structure). Once these features were reconsidered as Fase-1 Must-haves supporting the core loop's engagement, the Maps SDK choice needed resolving for real, not left as an Open Question.

## Decision

Use MapKit (native Apple framework) for both live tracking maps and static route rendering — `MKMapView` wrapped via `UIViewRepresentable`, not SwiftUI's `Map` type.

## Alternatives Considered

### Alternative 1: Mapbox
- **Pros**: More customizable styling; was the original assumption in early cost-structure planning.
- **Cons**: Per-request billing — the exact cost objection that originally justified deferring route maps to Fase 4 as a Non-Goal at all. A third-party SDK dependency, in a project that already deliberately removed third-party dependency risk from its most critical path (ADR-0001, ADR-0003).
- **Why not**: The features this project needs (show position + polyline from already-local data, no routing/geocoding) don't require Mapbox's advanced capabilities — MapKit satisfies the actual requirement at zero marginal cost.

### Alternative 2: SwiftUI's native `Map` type instead of `MKMapView`/`UIViewRepresentable`
- **Pros**: More idiomatic SwiftUI, less `UIViewRepresentable` bridging boilerplate.
- **Cons**: SwiftUI `Map`'s polyline overlay support (`MapPolyline`) is iOS 17+, but the project's deployment target is locked at iOS 16.0 (ADR-0001, T0.2 DoD) — using it would require an availability fork for the one platform version this app still supports.
- **Why not**: `MKMapView` is the only option that renders a polyline without an iOS-version fork, given the already-locked iOS 16 minimum (Round 7 finding B7-7).

## Consequences

### Positive
- Zero per-request cost — included in the Apple Developer Program fee already budgeted, removing an entire line item from the cost structure (lean-canvas.md §7 correction) rather than replacing it with a different cost.
- No third-party SDK dependency added, consistent with the project's broader "prefer native over third-party in critical/cost-sensitive paths" pattern (ADR-0001, ADR-0003).
- Reverses the prior Non-Goal cleanly — the original objection (cost) is structurally gone, not just deprioritized.

### Negative
- User position must be driven by a **custom annotation** fed from `RunViewModel`'s own published state — `MKMapView.showsUserLocation`/SwiftUI `UserAnnotation` are explicitly forbidden (Round 7 finding B7-8), since those start MapKit's own internal location subscription invisibly, violating both product-spec §4.8 AC3 ("no new GPS request") and architecture.md §3's layering rule (only the Data/Sync layer may talk to `CLLocationManager`) without showing up in any `CLLocationManager` call-site grep. This is an easy trap for a future contributor unfamiliar with this constraint.
- Less styling/customization flexibility than Mapbox would have offered — acceptable since the feature scope (position + polyline, no routing/geocoding) doesn't need it.

### Risks
- None significant — this is a well-understood native framework with no per-request billing risk to grow into at scale, unlike Mapbox would have been.
