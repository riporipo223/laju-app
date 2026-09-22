# ADR-0002: Core Data over SwiftData for local persistence

**Date**: 2026-09-10 (Fase 0, decided alongside the Swift pivot — tech-spec.md §1)
**Status**: accepted
**Deciders**: Project lead

## Context

The mobile client needs local, offline-first persistence for `Run` records that carry a substantial amount of sync/reconciliation state on top of the locally-computed fields: `syncStatus` (client-only), `serverRunId`, `serverStatus`, `flagConfidence`, `anomalyFlags`, `finalPointsAwarded`, `resolvedAt` (server-mirror attributes, T0.6), plus a separate single-instance `SyncMeta` entity for the reconciliation cursor (`lastReconciledAt`, `lastReconcileAttemptAt`, tech-spec.md §3 step 7). SwiftData is Apple's newer, more declarative persistence framework (iOS 17+), but was still relatively new at the time of this decision.

## Decision

Use Core Data for local persistence, modeled as an `.xcdatamodeld` with `Run` and `SyncMeta` entities.

## Alternatives Considered

### Alternative 1: SwiftData
- **Pros**: More modern, declarative API; less boilerplate for simple model definitions; tighter SwiftUI integration (`@Query`).
- **Cons**: Was relatively new and less battle-tested for the kind of sync/reconciliation complexity this project already had designed (tech-spec.md §2.4.1, §3) — many fields mirror server state and get updated asynchronously by a reconciliation loop (T2.14d), which is exactly the kind of complex, partially-server-driven local state pattern Core Data (with `NSFetchedResultsController`/`@FetchRequest` and direct `NSManagedObjectContext` control) is more proven for.
- **Why not**: The project's sync/reconciliation design was already committed to before this decision, and it's a genuinely complex pattern (see ADR-0010) — not the simple-CRUD case SwiftData is strongest for at the time. Maturity for this specific complexity class mattered more than API ergonomics.

### Alternative 2: A third-party persistence library (e.g. Realm)
- **Pros**: Cross-platform potential, some ergonomic wins over Core Data.
- **Cons**: Another third-party dependency in a project that just removed one third-party risk layer (ADR-0001) specifically to reduce dependency risk in critical paths.
- **Why not**: Contradicts the same reasoning that drove the native pivot — prefer platform-native tools over third-party dependencies where the platform-native option is mature enough, which Core Data is.

## Consequences

### Positive
- Mature, well-understood behavior for the sync/reconciliation complexity this project needs (partial server-mirror updates, background context handling).
- `NSFetchedResultsController`/`@FetchRequest` integrates cleanly with SwiftUI's `ObservableObject` state layer (architecture.md §3) without needing a third-party bridge.
- Local schema was designed from T0.6 onward with the sync/server-mirror attributes and `SyncMeta` entity present from the start — no later migration was needed to add them when Fase 2 sync landed.

### Negative
- More boilerplate than SwiftData's declarative model definitions.
- `NSPersistentContainer(name:)` re-parses the model on every `init` if not cached — this caused a real bug (T0.6: a Core Data entity-ambiguity error when two `PersistenceController` instances existed in one process, e.g. the app's `.shared` alongside a test's in-memory instance). Fixed by caching the parsed model in a `static let`, but this is a Core Data-specific footgun SwiftData's `ModelContainer` handles differently.

### Risks
- If SwiftData matures significantly and the project later wants its ergonomic/declarative benefits, a migration would be a non-trivial rewrite of the persistence layer. Not a near-term concern — no migration is planned.
- **Encryption at rest is inherited, not decided** (added 2026-09-17, security-review.md SEC-2): this decision carries an at-rest protection consequence that was never examined when it was taken. The Core Data SQLite store holds `Run.gpsRoute` — precise location history, the most sensitive data on the device — and no `NSFileProtection` class is specified for it anywhere, so the platform default applies by omission. The choice is genuinely constrained here rather than free: background location writes while the device is locked rule out `NSFileProtectionComplete`. See security-review.md SEC-2 for the analysis and the likely resolution.
