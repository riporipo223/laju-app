/**
 * T2.21 release-gate check: runs T2.6b's anti-cheat fixture corpus against the *deployed* backend over real
 * HTTP with a genuine Supabase Auth JWT — T2.13's own suite calls the route handlers in-process, so this is
 * the "green in the release environment, not just locally" evidence — and measures `POST /api/runs` latency
 * (PERF-1). Creates one synthetic user and removes everything it wrote.
 *
 *   (from backend/)  npx tsx --env-file=.env.local scripts/verify-release.ts [baseUrl] [latencySamples]
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createClient } from "@supabase/supabase-js";
import { createTestAuthUser } from "../test-support/auth";

const baseUrl = process.argv[2] ?? "https://backend-eight-gules-56.vercel.app";
const latencySamples = Number(process.argv[3] ?? 20);

const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const anon = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

const fixture = (name: string) =>
  JSON.parse(readFileSync(join(process.cwd(), "fixtures", "gps-routes", `${name}.json`), "utf-8"));

let counter = 0;
async function submit(jwt: string, name: string) {
  const f = fixture(name);
  counter++;
  const started = performance.now();
  const res = await fetch(`${baseUrl}/api/runs`, {
    method: "POST",
    headers: { authorization: `Bearer ${jwt}`, "content-type": "application/json" },
    body: JSON.stringify({
      started_at: new Date(Date.now() + counter * 1000).toISOString(),
      distance_meters: f.distance_meters,
      duration_seconds: f.duration_seconds,
      gps_route: f.gps_route,
    }),
  });
  const ms = Math.round(performance.now() - started);
  return { status: res.status, ms, json: (await res.json()) as { status: string; anomaly_flags: string[] } };
}

const checks: { label: string; pass: boolean; detail: string }[] = [];
const check = (label: string, pass: boolean, detail = "") => checks.push({ label, pass, detail });
const hasPrefix = (flags: string[], prefix: string) => flags.some((flag) => flag.startsWith(prefix));

async function main() {
  const email = `t221-${Date.now()}@laju-test.local`;
  const session = await createTestAuthUser(admin, anon, email);
  const jwt = session.accessToken;
  const { data: userRow, error: userError } = await admin
    .from("user")
    .insert({
      auth_user_id: session.authUserId,
      email,
      username: `t221${Date.now()}`,
      // region_* no longer set (2026-09-22, D1 reversed — product-spec.md §4.1). The columns were
      // physically dropped by migration 20260923090000, applied 2026-09-23.
    })
    .select("id")
    .single();
  if (userError || !userRow) throw new Error(`user row: ${userError?.message}`);

  try {
    for (const name of ["clean-negative-control-easy-jog", "clean-negative-control-fast-run"]) {
      const r = await submit(jwt, name);
      check(`${name}: validated, zero flags`, r.status === 201 && r.json.status === "validated" && r.json.anomaly_flags.length === 0, `${r.status} ${r.json.status} ${JSON.stringify(r.json.anomaly_flags)}`);
    }
    const expectations: [string, (flags: string[]) => boolean][] = [
      ["pace-cap-breach", (f) => f.includes("pace_cap_exceeded")],
      ["gps-speed-jump", (f) => hasPrefix(f, "gps_speed_jump_segment_")],
      ["teleport", (f) => hasPrefix(f, "distance_duration_sanity_segment_")],
      ["combined-anomalies", (f) => f.includes("pace_cap_exceeded") && hasPrefix(f, "gps_speed_jump_segment_")],
    ];
    for (const [name, expectFlags] of expectations) {
      const r = await submit(jwt, name);
      check(`${name}: flagged/rejected with its own flag`, r.json.status !== "validated" && expectFlags(r.json.anomaly_flags), `${r.status} ${r.json.status} ${JSON.stringify(r.json.anomaly_flags)}`);
    }

    const times: number[] = [];
    for (let i = 0; i < latencySamples; i++) times.push((await submit(jwt, "clean-negative-control-easy-jog")).ms);
    const sorted = [...times].sort((a, b) => a - b);
    const p = (q: number) => sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * q) - 1)];
    console.log(`POST /api/runs latency over ${latencySamples} sequential calls (ms): median ${p(0.5)}, p95 ${p(0.95)}, max ${sorted[sorted.length - 1]}`);
    console.log(`  raw: ${times.join(",")}`);
    check("POST /api/runs p95 within tech-spec.md §4's 1.5s budget", p(0.95)! < 1500, `p95 ${p(0.95)} ms`);
  } finally {
    await admin.from("point_transaction").delete().eq("user_id", userRow.id);
    await admin.from("run").delete().eq("user_id", userRow.id);
    await admin.from("user").delete().eq("id", userRow.id);
    await admin.auth.admin.deleteUser(session.authUserId);
  }

  for (const c of checks) console.log(`${c.pass ? "PASS" : "FAIL"}  ${c.label}${c.detail ? `  [${c.detail}]` : ""}`);
  const failed = checks.filter((c) => !c.pass).length;
  console.log(`\n${checks.length - failed}/${checks.length} passed against ${baseUrl}`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error(error);
  process.exit(2);
});
