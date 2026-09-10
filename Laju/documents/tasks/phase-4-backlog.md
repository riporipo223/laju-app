# Phase 4 — Backlog (not scheduled)

Source: [development-plan.md](../development-plan.md) Fase 4

This phase is explicitly **out of scope for execution now**. Listed at
high level only, so these items are known and deliberately deferred, not
forgotten. Do not break these down into granular tasks until the phase is
actually scheduled — doing so now would be speculative work against
requirements that haven't been validated yet (product-spec.md §5
Non-goals explains why each is deferred).

- **T4.1 — Circle / Clan / Club** (data model + UI). Depends on the `club_id`
  field already reserved on `User` (database-api-spec.md §1) and the
  sketched `Club` entity never migrated in Fase 2.
- **T4.2 — Club War.** Depends on T4.1.
- **T4.3 — Matchmaking between circles.** Depends on T4.1.
- **T4.4 — Monetization: seasonal pass.**
- **T4.5 — Monetization: advanced statistics.**
- **T4.6 — Monetization: exclusive badge.**
- **T4.7 — Monetization: premium profile.**
- **T4.8 — B2B dashboard: running club.**
- **T4.9 — B2B dashboard: event organizer.**
- **T4.10 — Route map visualization** (Mapbox integration, per
  tech-spec.md §1 Maps SDK row).
- **T4.11 — Android support** — postponed indefinitely, no timeline
  (platform decision, not tech-debt — tech-spec.md §1). Would require its
  own tracking mechanism decision (Android has no `CLLocationManager`
  equivalent) and its own local persistence choice, not a direct port of
  the iOS implementation.
- **T4.12 — Redis-backed real-time global leaderboard cache** — Open
  Question in architecture.md §4, only relevant if precompute freshness
  (≤15 min) proves insufficient at scale.
- **T4.13 — Native iOS platform integrations** (Live Activities, Dynamic
  Island, HealthKit, WidgetKit) — capabilities newly available now the app
  is Swift-native, explicitly not v1 scope (tech-spec.md §1,
  development-plan.md Fase 4, mvp-report.md §8). Pivot introduced
  capability, not a feature request — do not start until Fase 1–3 have
  shipped.
