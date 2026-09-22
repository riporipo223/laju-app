# ADR-0001: Native Swift + SwiftUI over React Native

**Date**: 2026-09-10 (documented retroactively — this decision predates the repository's git history; the first commit already ships the native SwiftUI skeleton)
**Status**: accepted
**Deciders**: Project lead

## Context

Laju's core loop depends entirely on reliable background GPS tracking during a 30-90 minute run, with the app backgrounded or the screen locked most of that time. The project originally targeted React Native, using a third-party background-geolocation library (`react-native-background-geolocation`) to bridge to native location APIs. That library became a standing risk item: an entire gate task (the pre-pivot equivalent of T0.9) existed solely to validate its reliability before any further work could proceed, and its behavior under iOS background suspension/termination was the single biggest unknown blocking Fase 0.

## Decision

Rebuild the mobile client as a native Swift + SwiftUI app (minimum iOS 16), using `CLLocationManager` directly. Android support is postponed indefinitely with no timeline (tech-spec.md §1, mvp-report.md §8) — v1 launches iOS-exclusive.

## Alternatives Considered

### Alternative 1: React Native + `react-native-background-geolocation`
- **Pros**: Cross-platform (iOS + Android) from one codebase; team already had RN/TypeScript familiarity; faster initial UI iteration.
- **Cons**: Bridges to native location APIs through a third-party library and a JS thread — added a dependency-risk layer directly in the most safety-critical path of the product (background GPS reliability). Bridge/JS-thread overhead is a real concern for a feature this battery- and reliability-sensitive.
- **Why not**: The third-party library's reliability was never validated and became a blocking gate on its own — removing it (by going native) removes the risk layer instead of spending a task validating it.

### Alternative 2: React Native + a different background-location library
- **Pros**: Keeps cross-platform reach while swapping the specific risky dependency.
- **Cons**: Still bridges to native location APIs through a third-party abstraction — the core risk (an unvalidated dependency in the critical path) is the same shape, just a different library name.
- **Why not**: Doesn't address the structural problem (third-party risk layer between the app and `CLLocationManager`), only relocates it.

## Consequences

### Positive
- No bridge/JS-thread overhead for background GPS — direct `CLLocationManager` access.
- Removes an entire class of third-party dependency risk from the most safety-critical code path.
- iOS 16 minimum is broad enough in practice while still supporting the background location capability the product needs.
- MVVM (SwiftUI Views → ViewModels → Model/services) maps cleanly onto the already-designed Presentation/State/Data-Sync layering (architecture.md §3) — porting the design, not redesigning it.

### Negative
- Full rewrite cost at the point of pivot — all RN-era UI work was discarded.
- Loses cross-platform reach; Android becomes a from-scratch effort later, with its own tracking-mechanism and persistence decisions (no direct port of the iOS implementation is possible — Android has no `CLLocationManager` equivalent).
- Client (Swift) and server (TypeScript) can no longer share a single literal source file for the point formula — replaced by a fixture-parity strategy (see ADR-0007).

### Risks
- Android is postponed with no committed timeline — this is a deliberate platform decision (not technical debt), but it does mean the addressable market is iOS-only for the foreseeable v1 lifetime. Mitigation: none needed at this stage: the core-loop hypothesis (product-spec.md §1) must be validated single-platform before a second platform is worth the investment.
