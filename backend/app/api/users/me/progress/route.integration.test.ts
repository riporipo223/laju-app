/**
 * T2.15 — Layer 3 (Integration): real `PointTransaction` ledger rows, written through the real
 * `recordRunPointsAndUpdateAggregate` (T2.12c), then read back through the real `GET
 * /api/users/me/progress` handler — proving the response genuinely reflects the ledger, not just a mocked
 * shape. Requires real credentials, same skip-gracefully pattern as the other integration files.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const hasRealCredentials = Boolean(
  process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

describe.skipIf(!hasRealCredentials)("GET /api/users/me/progress — real DB", () => {
  let authUserId: string;
  let userId: string;
  let jwt: string;
  let supabaseAdmin: import("@supabase/supabase-js").SupabaseClient;
  let GET: (request: Request) => Promise<Response>;
  let recordRunPointsAndUpdateAggregate: (userId: string, runId: string, amount: number) => Promise<unknown>;

  beforeAll(async () => {
    const { createClient } = await import("@supabase/supabase-js");
    supabaseAdmin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const email = `t215-${Date.now()}@laju-test.local`;
    const password = crypto.randomUUID();
    const { data: created, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (createError || !created.user) throw new Error(`Could not create test auth user: ${createError?.message}`);
    authUserId = created.user.id;

    const anonClient = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const { data: signIn, error: signInError } = await anonClient.auth.signInWithPassword({ email, password });
    if (signInError || !signIn.session) throw new Error(`Could not sign in test user: ${signInError?.message}`);
    jwt = signIn.session.access_token;

    const { data: userRow, error: userError } = await supabaseAdmin
      .from("user")
      .insert({ auth_user_id: authUserId, email, username: `t215user${Date.now()}` })
      .select("id")
      .single();
    if (userError || !userRow) throw new Error(`Could not create test user row: ${userError?.message}`);
    userId = userRow.id;

    ({ GET } = await import("./route"));
    ({ recordRunPointsAndUpdateAggregate } = await import("@/lib/point-transaction"));
  }, 30000);

  afterAll(async () => {
    if (userId) {
      await supabaseAdmin.from("point_transaction").delete().eq("user_id", userId);
      await supabaseAdmin.from("run").delete().eq("user_id", userId);
      await supabaseAdmin.from("user").delete().eq("id", userId);
    }
    if (authUserId) await supabaseAdmin.auth.admin.deleteUser(authUserId);
  }, 30000);

  function get() {
    return GET(new Request("https://example.com/api/users/me/progress", { headers: { authorization: `Bearer ${jwt}` } }));
  }

  it("rejects unauthenticated requests", async () => {
    const res = await GET(new Request("https://example.com/api/users/me/progress"));
    expect(res.status).toBe(401);
  });

  it("starts a fresh user at zero points, level 1", async () => {
    const res = await get();
    const json = await res.json();
    expect(json).toEqual({ total_points: 0, current_level: 1, points_to_next_level: 100, trust_score: 1 });
  });

  it("reflects real PointTransaction ledger writes, not a cached/separate counter", async () => {
    const { data: run1 } = await supabaseAdmin
      .from("run")
      .insert({ user_id: userId, status: "validated", anomaly_flags: [] })
      .select("id")
      .single();
    const { data: run2 } = await supabaseAdmin
      .from("run")
      .insert({ user_id: userId, status: "validated", anomaly_flags: [] })
      .select("id")
      .single();
    if (!run1 || !run2) throw new Error("Could not seed run rows");

    await recordRunPointsAndUpdateAggregate(userId, run1.id, 400);
    await recordRunPointsAndUpdateAggregate(userId, run2.id, 840);

    const { data: ledgerRows, error: ledgerError } = await supabaseAdmin
      .from("point_transaction")
      .select("amount")
      .eq("user_id", userId);
    if (ledgerError) throw new Error(`Could not read ledger: ${ledgerError.message}`);
    const ledgerSum = (ledgerRows ?? []).reduce((sum: number, row: { amount: number }) => sum + row.amount, 0);
    expect(ledgerSum).toBe(1240); // independent check that the ledger itself has the expected sum

    const res = await get();
    const json = await res.json();
    expect(json.total_points).toBe(ledgerSum);
    expect(json.total_points).toBe(1240);
    expect(json.current_level).toBe(4); // highest threshold <= 1240 is level 4 (700)
    expect(json.points_to_next_level).toBe(260); // level 5 threshold 1500 - 1240
    expect(json.trust_score).toBe(1); // untouched by this test, still the default
  });
});
