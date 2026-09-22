# ADR-0007: Shared fixture file for point-formula parity, not blind server trust

**Date**: 2026-09-10, formula revised with an additional gate 2026-09-13 (tech-spec.md §2.2b)
**Status**: accepted
**Deciders**: Project lead

## Context

Before the Swift pivot, `packages/shared-types/point-formula.ts` was one literal TypeScript file imported by both the React Native client and the Next.js server — divergence between client and server point calculations was structurally impossible, enforced by the compiler/import graph. After the pivot, the client (Swift) and server (TypeScript) are different languages with no possible literal shared source file. The server is still the authoritative source of truth for the points a user is actually awarded (tech-spec.md §2.4) — but that alone doesn't prevent the client's *optimistic estimate* from silently drifting out of sync with the server's real formula, which would make the "instant reward" UX (product-spec AC 4.3.1) feel wrong even though the final number is always correct.

## Decision

Define the formula textually once (tech-spec.md §2.2–§2.3) as the spec. Maintain a shared fixture file, `shared/point-formula.fixtures.json` — an array of `{input: {distance_km, avg_pace_sec_per_km, streak_days}, expected_points}` test vectors, committed once in the monorepo and read by **both** sides' test suites (`XCTest` on iOS, `vitest`/`jest` on the backend). Each side asserts its own `calculatePoints` implementation matches every fixture row. A parity test also fails outright if the fixture file is empty, so neither side can pass this check against a vacuous fixture.

## Alternatives Considered

### Alternative 1: Trust the server blindly, don't bother keeping the client formula in sync
- **Pros**: Simplest possible approach — the client estimate doesn't matter since the server is authoritative anyway.
- **Cons**: The core product hypothesis (product-spec §1) depends on the *instant* reward moment feeling right, in under 2 seconds, before any server round-trip. A client estimate that's frequently, silently wrong undermines that experience even though the eventual real number is correct — it would erode trust in the "instant" half of "instant reward."
- **Why not**: Rejected specifically because product-spec AC 4.3.1's UX requirement depends on the local estimate being *meaningfully* close to correct, not merely present.

### Alternative 2: Manually keep both implementations in sync by code review discipline alone, no automated check
- **Pros**: No extra fixture-file machinery to maintain.
- **Cons**: Relies entirely on a human reviewer noticing a formula change on one side wasn't mirrored on the other — exactly the kind of silent-drift risk a shared compiler used to prevent automatically before the pivot.
- **Why not**: Removes the automated safety net the pre-pivot architecture had, replacing it with pure vigilance — a strictly worse guarantee for a formula this central to fairness across the whole user base.

## Consequences

### Positive
- A fixture-parity test failure gives an immediate, automated signal the moment either side's formula changes without the other being updated to match — restores (via test infrastructure, not the compiler) most of the safety the old shared-file approach had.
- `repo-coding-rules.md` §4's PR checklist requires touching `shared/point-formula.fixtures.json` and passing both sides' parity tests whenever the point formula or anti-cheat logic changes — the process, not just the tooling, is designed around this.
- The empty-fixture guard means the parity mechanism can never silently become a no-op (e.g. from an accidental fixture-file reset).

### Negative
- The fixture file must be manually updated any time §2.2/§2.3 changes (e.g. tuning `STREAK_BONUS_PER_DAY` with real data later) — this is a manual step, not automatic, and depends on the PR checklist actually being followed.
- Divergence is caught at test time, not at compile time — a change that ships without running tests (or with tests accidentally skipped) could still land a real mismatch, something the old shared-file approach could not have allowed at all.

### Risks
- The fixture file's coverage is only as good as the vectors it contains — a formula edge case not represented as a fixture row could diverge on both sides without either parity test catching it. Mitigation: T1.1's own DoD required covering every pace-bracket boundary, streak-cap edge, and the zero-distance/minimum-distance gate explicitly (see ADR-0009), not an arbitrary sample.
