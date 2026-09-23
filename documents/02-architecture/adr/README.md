# Architecture Decision Records

This log formalizes architecture decisions already made and verified through 7+ rounds of audit plus real device/code evidence. It is not a rethink of these decisions — each ADR extracts and formalizes rationale that already existed in tech-spec.md, product-spec.md, database-api-spec.md, and prior audit history.

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0001](0001-native-swift-swiftui-over-react-native.md) | Native Swift + SwiftUI over React Native | accepted | 2026-09-10 (documented retroactively) |
| [0002](0002-core-data-over-swiftdata.md) | Core Data over SwiftData for local persistence | accepted | 2026-09-10 |
| [0003](0003-clocationmanager-direct-over-third-party.md) | `CLLocationManager` directly, no third-party GPS library | accepted | 2026-09-10 |
| [0004](0004-stationary-anchor-anti-drift-strategy.md) | Stationary-anchor drift filter, not a simple distance threshold | accepted | 2026-09-11, hardened 2026-09-12 |
| [0005](0005-nextjs-supabase-vercel-backend-stack.md) | Next.js + Supabase + Vercel as the backend stack | accepted — recommendation, not final on DB choice | 2026-09-10 |
| [0006](0006-postgres-over-firestore.md) | PostgreSQL (via Supabase) over Firestore | accepted — recommendation, not final | 2026-09-10 |
| [0007](0007-fixture-parity-file-for-cross-language-formula-consistency.md) | Shared fixture file for point-formula parity, not blind server trust | accepted | 2026-09-10, revised 2026-09-13 |
| [0008](0008-server-anti-cheat-separate-from-client-sanity-filter.md) | Server-side anti-cheat as a separate architecture from client-side sanity filtering | accepted | 2026-09-10, hardened Fase 1 |
| [0009](0009-minimum-distance-gate-anti-farming.md) | Minimum-distance gate on the point formula (anti-farming) | accepted | 2026-09-13 |
| [0010](0010-cursor-based-status-reconciliation.md) | Cursor-based status reconciliation (server-issued cursor, ASC + has_more) | accepted | 2026-09-13 |
| [0011](0011-mapkit-over-mapbox.md) | MapKit over Mapbox for live/static route maps | accepted | 2026-09-12 |
| [0012](0012-periodic-timer-auto-pause-evaluation.md) | Periodic timer for auto-pause evaluation, not reactive-per-fix | **superseded** (feature removed 2026-09-22, not replaced by another ADR) | 2026-09-13 |
| [0013](0013-append-only-ledger-and-precomputed-leaderboard.md) | Append-only PointTransaction ledger with a separately precomputed leaderboard table | accepted | 2026-09-10, extended through Round 7 |
| [0014](0014-event-scale-permission-rule.md) | Event-scale reach is Laju-exclusive — no self-serve, any tier | accepted | 2026-09-23 |

## Lifecycle

```
proposed → accepted → [deprecated | superseded by ADR-NNNN]
```

13 of the 14 ADRs above are `accepted`; ADR-0012 is `superseded` (auto-pause removed by product decision, 2026-09-22 — see the note at the top of that ADR). ADR-0005 and ADR-0006 carry an explicit qualifier: tech-spec.md §1 flags the backend framework/hosting choice as a strong recommendation and the database choice as reserved for final PM confirmation.

The decisions tech-spec.md §1 marks **locked** are the four stack-table rows: mobile client ([ADR-0001](0001-native-swift-swiftui-over-react-native.md)), GPS tracking ([ADR-0003](0003-clocationmanager-direct-over-third-party.md)), local storage ([ADR-0002](0002-core-data-over-swiftdata.md)), and Maps SDK ([ADR-0011](0011-mapkit-over-mapbox.md), locked 2026-09-12). The remaining ADRs record decisions taken outside that table — in tech-spec.md's design sections, in the API spec, or in response to on-device evidence — and are no less binding for it; they simply are not stack choices.
