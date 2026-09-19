/**
 * Regression guard for the Fase 2 audit finding (2026-09-19): every `public` table had RLS off and full
 * grants to `anon`, while the anon key ships inside the app and the repo — so anyone could read or rewrite the
 * database over PostgREST. This calls PostgREST exactly as an attacker would (public anon key, no login) and
 * requires every table to refuse both reads and writes. Runs against the real project; skips without credentials.
 */
import { describe, expect, it } from "vitest";

const hasRealCredentials = Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

const TABLES = ["user", "run", "point_transaction", "season", "leaderboard_entry", "leaderboard_scope"];

describe.skipIf(!hasRealCredentials)("the public anon key cannot touch application tables", () => {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
  const headers = { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json" };

  it.each(TABLES)("%s: SELECT is refused", async (table) => {
    const res = await fetch(`${url}/rest/v1/${table}?select=*&limit=1`, { headers });
    expect(res.status, `anon SELECT on ${table} must not succeed`).toBeGreaterThanOrEqual(400);
  });

  it.each(TABLES)("%s: INSERT / UPDATE / DELETE are refused", async (table) => {
    const insert = await fetch(`${url}/rest/v1/${table}`, { method: "POST", headers, body: JSON.stringify({}) });
    expect(insert.status, `anon INSERT on ${table} must not succeed`).toBeGreaterThanOrEqual(400);

    const update = await fetch(`${url}/rest/v1/${table}?id=eq.00000000-0000-0000-0000-000000000000`, {
      method: "PATCH",
      headers,
      body: JSON.stringify({}),
    });
    expect(update.status, `anon UPDATE on ${table} must not succeed`).toBeGreaterThanOrEqual(400);

    const remove = await fetch(`${url}/rest/v1/${table}?id=eq.00000000-0000-0000-0000-000000000000`, {
      method: "DELETE",
      headers,
    });
    expect(remove.status, `anon DELETE on ${table} must not succeed`).toBeGreaterThanOrEqual(400);
  });
});
