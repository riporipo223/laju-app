# ADR-0014: Event-scale reach is Laju-exclusive — no self-serve, any tier

**Date**: 2026-09-23
**Status**: accepted
**Deciders**: PM, decided while reframing the EO Dashboard (lean-canvas.md §2/§6) and scoping Club
War (product-spec.md §4.19)

## Context

Two features under active discussion in the same session both raise the same question: who gets to
reach or notify a large slice of the user base, and how. The EO (Event Organizer) Dashboard was
originally conceived as a self-serve B2B SaaS tool — an EO signs up, gets dashboard access, and runs
their own event. Separately, Club War needed a rule about whether a self-serve Club owner/admin
could ever trigger something that reaches users outside their own club's ≤3-club match.

Both questions resolve to the same underlying principle, so it is recorded once, generally, rather
than as two separate feature-specific rules that could quietly drift apart later.

## Decision

**Anything that reaches or notifies the ENTIRE user base is Laju-exclusive.** No account tier —
Free, Premium, or any future B2B tier — gets self-serve access to whole-app-scale reach, regardless
of what else that tier is allowed to do. Concretely:

- **EO Dashboard reframed as a managed service, not a self-serve tool** (lean-canvas.md §2/§6): EO
  clients never get dashboard access. Laju's own team creates and manages events on their behalf.
  This was the immediate trigger for writing this rule down — an EO running their own event-wide
  campaign is exactly the "whole user base" reach this ADR restricts.
- **Club War stays bounded, and deliberately doesn't need this restriction**: a Club War's reach is
  the ≤3 clubs actually entered (product-spec.md §4.19), never the whole user base, so it can stay
  self-serve by a Premium Club's owner/admin without conflicting with this rule. This ADR is *why*
  that boundary matters, not just an incidental detail of §4.19's scope.
- Any future feature (push campaigns, platform-wide announcements, cross-club events beyond a single
  Club War, etc.) must be checked against this rule before being scoped as self-serve.

## Alternatives Considered

### Alternative 1: Gate whole-app reach by tier (e.g. "Enterprise" B2B tier gets it)
- **Pros**: Familiar SaaS pattern; potential revenue lever.
- **Cons**: Whole-app reach is a trust and abuse-surface decision, not a feature a paying customer
  should be able to buy into — a malicious or careless EO client with self-serve whole-app reach is
  a real risk (spam, misleading claims, moderation gap) that a managed-service model avoids by
  construction.
- **Why not**: Rejected by the PM when reframing the EO Dashboard — see the "requesting client, not
  active dashboard user" framing in lean-canvas.md §2.

### Alternative 2: Leave it undecided per-feature, re-litigate each time
- **Pros**: Maximum flexibility per feature.
- **Cons**: Exactly the drift this ADR exists to prevent — the EO Dashboard and Club War discussions
  independently arrived at compatible-but-unstated answers to the same question; the next feature
  that touches broad reach would have no established precedent to check against.
- **Why not**: The whole point of recording this as a general architectural principle rather than a
  feature-local note.

## Consequences

- Any new feature proposal that includes "notify/reach all users" as a self-serve capability, at any
  tier, should be flagged against this ADR before being scoped.
- The EO Dashboard's own name may no longer accurately describe what it is — flagged as an open
  question in lean-canvas.md §2, not resolved here.
- No code changes yet — this session's Part 4 work is docs-only (per its own scope); enforcement of
  this rule in actual EO-management tooling is future implementation work, not yet scoped as a task.
