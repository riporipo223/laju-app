# ADR-0005: Next.js + Supabase + Vercel as the backend stack

**Date**: 2026-09-10 (tech-spec.md §1, decided alongside the Swift pivot)
**Status**: accepted — **rekomendasi kuat, bukan keputusan final** (tech-spec.md §1 explicitly flags this row and the database row below it as PM-decidable, unlike the locked mobile-stack rows)
**Deciders**: Project lead (framework/hosting), flagged for explicit PM confirmation on the DB choice specifically

## Context

The mobile client pivoted to native Swift (ADR-0001), but the backend has no equivalent constraint — it's a separate deployable, callable from any client language via HTTP/JSON. The question was whether the backend stack should also change, or whether the pre-pivot Next.js/TypeScript choice (made when the client was also TypeScript/React Native) still made sense once the client no longer shared a language with it.

## Decision

Keep Next.js (App Router, API routes) + TypeScript as the backend framework, Vercel as hosting, Supabase (Postgres + Auth) as the database/auth layer.

## Alternatives Considered

### Alternative 1: Switch backend language/framework to match nothing in particular (e.g. Go, a Python framework)
- **Pros**: Could pick a framework optimized purely for backend concerns, unconstrained by any prior TypeScript investment.
- **Cons**: Throws away existing team familiarity with Next.js/TypeScript for no concrete technical gain — the client/server language split already exists regardless (Swift client, any-language server), so there's no cross-language sharing benefit to preserve or lose either way (see ADR-0007 for how point-formula parity is kept without literal code sharing).
- **Why not**: No evidence-based reason to pay a framework-switch cost when the original reason for choosing Next.js (team familiarity, admin/B2B dashboard reuse potential) is untouched by the mobile pivot.

### Alternative 2: A different managed Postgres/BaaS provider instead of Supabase
- **Pros**: Could shop for cheaper hosting or different feature sets.
- **Cons**: Supabase's integrated Postgres + Auth (JWT) avoids syncing two separate identity systems (e.g. Firebase Auth + a separate Postgres user table) — a concrete integration simplification for this project's specific auth needs.
- **Why not**: Not evaluated in depth — Supabase was accepted as the reasonable default given the Postgres decision (ADR-0006) and its Auth integration, without a documented alternative-provider bake-off. Flagged here as a real gap, not hidden.

## Consequences

### Positive
- No framework-switch cost paid; existing TypeScript backend investment (pre-pivot) carries forward unchanged.
- Supabase Auth (JWT) integrates directly with Postgres — no second identity system to keep in sync, and Row Level Security is available if needed later.
- Vercel Cron (v1) covers both scheduled jobs the product needs (leaderboard precompute, `resolve-flagged-runs`) without standing up separate worker infrastructure — tech-spec.md §1's background-jobs row notes a migration path (dedicated worker) if volume grows.
- Next.js/TypeScript can be reused for a future admin/B2B dashboard (club/EO tooling, Fase 4 backlog) without a second stack. *(Note 2026-09-23: neither dashboard is planned any more — the EO idea became Laju Branded Events (product-spec.md §4.21) and club admin tools moved into the app as a Premium feature (§4.24, T4.8 merged into T4.1). This consequence no longer applies; the stack decision itself is unaffected.)*

### Negative
- Backend and mobile client are now two fully separate languages/ecosystems with zero code sharing — every cross-cutting contract (point formula, API request/response shapes) must be kept in sync manually or via fixture files, not enforced by a shared compiler (see ADR-0007).
- This row of the stack table is explicitly marked "rekomendasi, bukan final" in tech-spec.md — a PM could still revisit it, meaning downstream Fase 2 work (already scaffolded, T2.1) is built on a stack that isn't formally locked the way the mobile stack is.

### Risks
- Vercel Cron's suitability at scale (leaderboard precompute within a 15-minute freshness window) is untested beyond the v1 target scale — architecture.md §4 already documents a Redis-backed read-through cache as an Open Question if this doesn't hold, not a first-choice design.
- Supabase-specific lock-in (Auth, managed Postgres) was not weighed against a general "self-hosted Postgres + hand-rolled JWT" alternative in writing — accepted as reasonable, not rigorously bake-off-tested.
- **Cross-border data transfer was not considered** (added 2026-09-17, security-review.md SEC-12): both Supabase and Vercel host outside Indonesia by default, while every v1 user is an Indonesian data subject (leaderboard scopes follow the Indonesian administrative hierarchy) and the data leaving the country includes precise location history. This has a narrow, cheap window — a hosting-region choice made at provisioning time — and an expensive one, a migration after production data exists. See security-review.md SEC-12; the underlying legal question needs qualified review, not a self-assessment.
