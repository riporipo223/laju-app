/**
 * T2.19 — Layer 3: the real `GET /api/leaderboard` handler over T2.18's real precomputed tables, with a
 * genuine Supabase Auth JWT for the caller. Proves the trust-threshold DoD item end to end: a user below the
 * cutoff never appears, ranks stay contiguous, and `me` reflects the same board. Skips without credentials.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const hasRealCredentials = Boolean(
  process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

// Transport blips from the CI runner (`TypeError: fetch failed`) are retried; real errors surface at once.
async function retryTransport<T extends { error: { message: string } | null }>(call: () => PromiseLike<T>): Promise<T> {
  let result = await call();
  for (let attempt = 0; attempt < 3 && result.error?.message.includes("fetch failed"); attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    result = await call();
  }
  return result;
}

interface EntryJson {
  rank: number;
  user_id: string;
  username: string;
  points: number;
}

describe.skipIf(!hasRealCredentials)("GET /api/leaderboard — real DB", () => {
  let admin: import("@supabase/supabase-js").SupabaseClient;
  let seasonId: string;
  let authUserId: string;
  let jwt: string;
  let callerId: string;
  let GET: (request: Request) => Promise<Response>;
  const userIds: string[] = [];
  const tag = `t219-${Date.now()}`;

  async function makeUser(label: string, trust: number, authId?: string) {
    const { data, error } = await retryTransport(() =>
      admin
        .from("user")
        .insert({
          email: `${tag}-${label}@laju-test.local`,
          username: `${tag}${label}`,
          display_name: `Name ${label}`,
          trust_score: trust,
          auth_user_id: authId ?? null,
        })
        .select("id")
        .single()
    );
    if (error || !data) throw new Error(`user insert failed: ${error?.message}`);
    userIds.push(data.id);
    return data.id as string;
  }

  async function addPoints(userId: string, amount: number) {
    const { data: run, error } = await retryTransport(() =>
      admin.from("run").insert({ user_id: userId, status: "validated", anomaly_flags: [] }).select("id").single()
    );
    if (error || !run) throw new Error(`run insert failed: ${error?.message}`);
    const { error: txError } = await retryTransport(() =>
      admin.from("point_transaction").insert({ user_id: userId, run_id: run.id, season_id: seasonId, amount, type: "run" })
    );
    if (txError) throw new Error(`transaction insert failed: ${txError.message}`);
  }

  async function rebuild() {
    const { error } = await retryTransport(() => admin.rpc("rebuild_global_leaderboard"));
    if (error) throw new Error(`rebuild failed: ${error.message}`);
  }

  async function get(query = "scope=global") {
    return GET(new Request(`https://example.com/api/leaderboard?${query}`, { headers: { authorization: `Bearer ${jwt}` } }));
  }

  beforeAll(async () => {
    const { createClient } = await import("@supabase/supabase-js");
    admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const anon = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

    const { data: season, error: seasonError } = await admin.from("season").select("id").eq("status", "active").single();
    if (seasonError || !season) throw new Error("no active season — T2.17's seed is required");
    seasonId = season.id;

    const email = `${tag}-caller@laju-test.local`;
    const password = crypto.randomUUID();
    const { data: created, error: createError } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (createError || !created.user) throw new Error(`auth user failed: ${createError?.message}`);
    authUserId = created.user.id;
    const { data: signIn, error: signInError } = await anon.auth.signInWithPassword({ email, password });
    if (signInError || !signIn.session) throw new Error(`sign-in failed: ${signInError?.message}`);
    jwt = signIn.session.access_token;

    callerId = await makeUser("caller", 1.0, authUserId);
    ({ GET } = await import("./route"));
  }, 60000);

  afterAll(async () => {
    if (userIds.length > 0) {
      await admin.from("leaderboard_entry").delete().in("user_id", userIds);
      await admin.from("point_transaction").delete().in("user_id", userIds);
      await admin.from("run").delete().in("user_id", userIds);
      await admin.from("user").delete().in("id", userIds);
    }
    if (authUserId) await admin.auth.admin.deleteUser(authUserId);
    await rebuild();
  }, 60000);

  it("rejects unauthenticated requests", async () => {
    const res = await GET(new Request("https://example.com/api/leaderboard?scope=global"));
    expect(res.status).toBe(401);
  });

  it("hides users below the trust cutoff, keeps ranks contiguous, and `me` agrees with the list", async () => {
    const high = await makeUser("high", 1.0);
    const boundary = await makeUser("boundary", 0.5); // exactly the cutoff → still shown (>=)
    const hidden = await makeUser("hidden", 0.49); // just below → hidden
    await addPoints(high, 300);
    await addPoints(hidden, 200); // would rank 2nd if trust were ignored
    await addPoints(boundary, 100);
    await addPoints(callerId, 50);
    await rebuild();

    const res = await get("scope=global&limit=100");
    expect(res.status).toBe(200);
    const json = await res.json();

    const mine = (json.entries as EntryJson[]).filter((entry) => userIds.includes(entry.user_id));
    expect(mine.map((entry) => entry.user_id)).toEqual([high, boundary, callerId]); // `hidden` absent
    expect(mine.map((entry) => entry.points)).toEqual([300, 100, 50]);
    expect(mine[0]?.username).toBe("Name high");

    // Rank consistency computed from the response itself (competition ranking: 1 + how many entries have
    // strictly more points) — so a gap where `hidden` would have sat would fail, without depending on
    // whether other rows exist on the shared board.
    const all = json.entries as EntryJson[];
    for (const entry of all) {
      expect(entry.rank).toBe(1 + all.filter((other) => other.points > entry.points).length);
    }
    expect(json.me).toEqual({ rank: mine[2]?.rank, points: 50 });
    expect(json).toMatchObject({ season_id: seasonId, scope: "global", insufficient_data: false });
    expect(typeof json.computed_at).toBe("string");
  }, 60000);

  it("respects limit", async () => {
    const json = await (await get("scope=global&limit=1")).json();
    expect(json.entries).toHaveLength(1);
  });

  it("a caller who drops below the cutoff disappears from the board and gets me: null", async () => {
    await admin.from("user").update({ trust_score: 0.4 }).eq("id", callerId);
    await rebuild();

    const json = await (await get("scope=global&limit=100")).json();
    expect((json.entries as EntryJson[]).some((entry) => entry.user_id === callerId)).toBe(false);
    expect(json.me).toBeNull();
  }, 60000);

  it("400s on a region scope until T3.4 ships", async () => {
    expect((await get("scope=provinsi&scope_id=DKI+Jakarta")).status).toBe(400);
  });
});
