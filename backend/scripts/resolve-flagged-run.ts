/**
 * T2.12b's manual-override runbook tool — "direct DB action, no admin UI" (task scope). Reuses
 * `resolveFlaggedRun` rather than asking an operator to hand-write the compensating-transaction/trust-
 * recompute SQL themselves, which is exactly the class of error this function exists to prevent.
 *
 * Usage (see documents/04-quality-security/anti-cheat-resolution-runbook.md for the full procedure):
 *   npx tsx --env-file=.env.local scripts/resolve-flagged-run.ts <run_id> <approved|rejected>
 *
 * `resolved_via` is always 'manual' here — the 'auto' path only exists for the LOW-confidence scheduled
 * job (T2.12f), never for a human running this script.
 */

import { resolveFlaggedRun } from "../lib/anti-cheat/resolve-flagged-runs";

const [runId, outcome] = process.argv.slice(2);

if (!runId || (outcome !== "approved" && outcome !== "rejected")) {
  console.error("Usage: resolve-flagged-run.ts <run_id> <approved|rejected>");
  process.exit(1);
}

await resolveFlaggedRun(runId, outcome, "manual");
console.log(`Run ${runId} resolved to '${outcome}' (resolved_via=manual).`);
