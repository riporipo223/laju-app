# ADR-0006: PostgreSQL (via Supabase) over Firestore

**Date**: 2026-09-10 (tech-spec.md §1)
**Status**: accepted — **rekomendasi, bukan keputusan final** (tech-spec.md §1 explicitly frames this as a trade-off note "untuk PM decide")
**Deciders**: Project lead (recommendation); final call reserved for PM

## Context

The leaderboard is the product's core competitive mechanic, and it needs granular regional queries: "top N per region (kecamatan/kabupaten-kota/provinsi), sorted by points, with tie-break, per season." The point ledger (`PointTransaction`) also needs to be an immutable, auditable append-only log with referential integrity to `User`/`Run`/`Season`. Firebase/Firestore was a familiar option for the team; Postgres via Supabase was the alternative.

## Decision

Use PostgreSQL (via Supabase) as the primary datastore.

## Alternatives Considered

### Alternative 1: Firebase / Firestore
- **Pros**: Familiar to the development team; fast initial setup; real-time listeners built in.
- **Cons**: "Top N per region, sorted, with tie-break" is native to SQL (`ORDER BY`, `PARTITION BY`, materialized views) but requires manual precompute plus layered denormalization in Firestore — more bug-prone and more expensive on read quota at scale. The point ledger's integrity (foreign keys to User/Run/Season, immutability) is enforceable at the database level in Postgres; in Firestore it would have to be maintained entirely in application code, with no database-level guarantee against a bug writing an orphaned or mutated ledger row.
- **Why not**: The leaderboard's core query shape and the ledger's core integrity requirement are both things Postgres does natively and Firestore does not — this isn't a stylistic preference, it's a structural fit question, and Postgres fits the product's two most important data-integrity requirements more directly.

## Consequences

### Positive
- Leaderboard ranking queries (`ORDER BY points DESC` per `(season_id, scope_type, scope_id)`) map directly to an indexed range scan (architecture.md §4) — no manual denormalization layer needed.
- `PointTransaction`'s foreign keys to `User`/`Run`/`Season` are enforced at the database level — a bug in application code cannot silently orphan or corrupt the ledger the way it could in a document store with no native referential integrity.
- Supabase pairs Postgres with JWT Auth directly (see ADR-0005), avoiding a second identity system.

### Negative
- Loses Firestore's built-in real-time listeners — any "live" leaderboard update would need to be built explicitly (not needed in v1, since leaderboard reads are precomputed on a 15-minute interval by design, not real-time — architecture.md §4).
- Team's existing Firestore familiarity (if any) doesn't carry forward; Postgres/SQL query-writing is a different skill investment.

### Risks
- This decision is explicitly flagged as a recommendation, not final — tech-spec.md §1 frames it as a trade-off note for the PM. If reversed later, every precompute job, ranking query, and the ledger's integrity model would need to be redesigned around Firestore's constraints instead — a significant rework, not a drop-in swap.
