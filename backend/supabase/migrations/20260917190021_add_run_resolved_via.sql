-- T2.11: trust_multiplier's LOW-confidence decay rule (tech-spec.md §2.4) exempts a flag ONLY when it
-- ended in auto-approve, not any approval. Nothing in the existing schema distinguishes "resolved by the
-- resolve-flagged-runs cron job" from "resolved by a human via the manual-override runbook" (tech-spec.md
-- §2.4.1) — both just set status='approved'. That distinction is a real prerequisite for T2.11's formula,
-- not a T2.12b concern: T2.12b calls trust_multiplier again when a flag resolves, it doesn't define how
-- resolution method is recorded. Nullable: null while a run is unresolved (validated, or still flagged).
alter table "run"
  add column "resolved_via" text
    check ("resolved_via" is null or "resolved_via" in ('auto', 'manual'));
