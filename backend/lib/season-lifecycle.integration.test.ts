/**
 * T3.6 — Season lifecycle against the real Supabase project. These tests TEMPORARILY change which season is active (that is
 * the thing being tested), so every test ends by restoring the real seasons to exactly the statuses they had, and the
 * test seasons (named `T36-…`) are always deleted. `advance_seasons` takes its clock as a parameter, so "time passing" is
 * simulated without waiting. Skips without credentials.
 */
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";

const hasRealCredentials = Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);

interface SeasonRow {
  id: string;
  name: string;
  status: string;
  start_at: string;
  end_at: string;
}

describe.skipIf(!hasRealCredentials)("season lifecycle — real database", () => {
  let admin: import("@supabase/supabase-js").SupabaseClient;
  let real: SeasonRow[] = [];
  let realActive: SeasonRow;

  const day = 86_400_000;
  const iso = (ms: number) => new Date(ms).toISOString();

  async function newSeason(label: string, startMs: number, endMs: number, status = "upcoming") {
    const { data, error } = await admin
      .from("season")
      .insert({ name: `T36-${label}-${Date.now()}`, start_at: iso(startMs), end_at: iso(endMs), status })
      .select("*")
      .single();
    if (error || !data) throw new Error(`could not create season: ${error?.message}`);
    return data as SeasonRow;
  }

  async function statuses() {
    const { data } = await admin.from("season").select("id, status");
    return new Map((data ?? []).map((row: { id: string; status: string }) => [row.id, row.status]));
  }

  async function activeCount() {
    const { count } = await admin.from("season").select("id", { count: "exact", head: true }).eq("status", "active");
    return count;
  }

  const advance = (nowMs: number) => admin.rpc("advance_seasons", { p_now: iso(nowMs) });
  const transition = (id: string, to: string) => admin.rpc("transition_season", { p_season: id, p_to: to });

  /** Transitions write a leaderboard_scope row per season (T3.7), which blocks deleting the season until it is removed too. */
  async function deleteTestSeasons() {
    const { data } = await admin.from("season").select("id").like("name", "T36-%");
    const ids = (data ?? []).map((row: { id: string }) => row.id);
    if (ids.length) {
      await admin.from("season_result").delete().in("season_id", ids); // frozen when a season ends (T3.8)
      await admin.from("leaderboard_scope").delete().in("season_id", ids);
    }
    await admin.from("season").delete().like("name", "T36-%");
  }

  /** Puts the real seasons back exactly as they were, and removes every test season. Order matters: the unique index. */
  async function restore() {
    await admin.from("season").update({ status: "ended" }).like("name", "T36-%");
    for (const season of real) await admin.from("season").update({ status: season.status }).eq("id", season.id);
    await deleteTestSeasons();
  }

  beforeAll(async () => {
    const { createClient } = await import("@supabase/supabase-js");
    admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    await deleteTestSeasons(); // leftovers of an interrupted earlier run
    const { data } = await admin.from("season").select("*").order("start_at");
    real = (data ?? []) as SeasonRow[];
    const active = real.filter((season) => season.status === "active");
    if (active.length !== 1) throw new Error(`expected exactly one real active season, found ${active.length}`);
    realActive = active[0]!;
  }, 60000);

  afterEach(async () => {
    await restore();
  }, 60000);

  afterAll(async () => {
    await restore();
    expect(await activeCount()).toBe(1); // production is left with exactly one active season
  }, 60000);

  it("the database itself refuses a second active season (unique index), not just the functions", async () => {
    const { error } = await admin.from("season").insert({
      name: `T36-dup-${Date.now()}`,
      start_at: iso(Date.parse(realActive.end_at) + day),
      end_at: iso(Date.parse(realActive.end_at) + 90 * day),
      status: "active",
    });
    expect(error?.code).toBe("23505");
    expect(await activeCount()).toBe(1);
  }, 60000);

  it("refuses a season that ends before it starts", async () => {
    const { error } = await admin.from("season").insert({
      name: `T36-bad-${Date.now()}`,
      start_at: iso(Date.parse(realActive.end_at) + 10 * day),
      end_at: iso(Date.parse(realActive.end_at) + day),
      status: "upcoming",
    });
    expect(error).not.toBeNull();
  }, 60000);

  it("transition_season: activating a season rolls the old active one over, leaving exactly one active", async () => {
    const next = await newSeason("next", Date.parse(realActive.end_at), Date.parse(realActive.end_at) + 90 * day);
    const { data, error } = await transition(next.id, "active");
    expect(error).toBeNull();
    expect(data[0]).toMatchObject({ from_status: "upcoming", to_status: "active", rolled_over: realActive.id });
    const after = await statuses();
    expect(after.get(next.id)).toBe("active");
    expect(after.get(realActive.id)).toBe("ended");
    expect(await activeCount()).toBe(1);
  }, 60000);

  it("transition_season refuses to end the only active season — that would leave runs with no season to score into", async () => {
    const { error } = await transition(realActive.id, "ended");
    expect(error?.message).toMatch(/only active season/);
    expect((await statuses()).get(realActive.id)).toBe("active");
  }, 60000);

  it("transition_season: illegal moves, unknown ids and bad targets all raise", async () => {
    const cancelled = await newSeason("cancel", Date.parse(realActive.end_at), Date.parse(realActive.end_at) + 30 * day);
    expect((await transition(cancelled.id, "ended")).error).toBeNull(); // upcoming → ended (cancel) is legal
    expect((await transition(cancelled.id, "active")).error?.message).toMatch(/illegal season transition ended/); // ended is final
    expect((await transition(realActive.id, "upcoming")).error?.message).toMatch(/target status must be active or ended/);
    expect((await transition("00000000-0000-0000-0000-000000000000", "active")).error?.message).toMatch(/does not exist/);
  }, 60000);

  it("advance_seasons does nothing before the active season's end", async () => {
    await newSeason("early", Date.parse(realActive.end_at), Date.parse(realActive.end_at) + 90 * day);
    const { data, error } = await advance(Date.parse(realActive.end_at) - day);
    expect(error).toBeNull();
    expect(data).toEqual([]);
    expect(await activeCount()).toBe(1);
  }, 60000);

  it("advance_seasons at the boundary ends the old season and activates its successor in one step", async () => {
    const next = await newSeason("succ", Date.parse(realActive.end_at), Date.parse(realActive.end_at) + 90 * day);
    const { data, error } = await advance(Date.parse(realActive.end_at) + 1000);
    expect(error).toBeNull();
    expect(data.map((row: { action: string }) => row.action)).toEqual(["ended", "activated"]);
    const after = await statuses();
    expect(after.get(realActive.id)).toBe("ended");
    expect(after.get(next.id)).toBe("active");
    expect(await activeCount()).toBe(1);
  }, 60000);

  it("advance_seasons never leaves the system without an active season: no successor → 'overrun', season stays active", async () => {
    const { data, error } = await advance(Date.parse(realActive.end_at) + 30 * day);
    expect(error).toBeNull();
    expect(data).toEqual([{ action: "overrun", season_id: realActive.id }]);
    expect((await statuses()).get(realActive.id)).toBe("active");
  }, 60000);

  it("with no active season at all, advance_seasons activates the earliest due upcoming one", async () => {
    await admin.from("season").update({ status: "ended" }).eq("id", realActive.id); // simulate a broken/empty state
    const first = await newSeason("first", Date.parse(realActive.end_at), Date.parse(realActive.end_at) + 60 * day);
    await newSeason("second", Date.parse(realActive.end_at) + 60 * day, Date.parse(realActive.end_at) + 120 * day);
    const { data } = await advance(Date.parse(realActive.end_at) + day);
    expect(data).toEqual([{ action: "activated", season_id: first.id }]);
    expect(await activeCount()).toBe(1);
  }, 60000);

  it("catches up several missed seasons one step at a time and lands on the current one", async () => {
    const base = Date.parse(realActive.end_at);
    const a = await newSeason("a", base, base + 30 * day);
    const b = await newSeason("b", base + 30 * day, base + 60 * day);
    const { data } = await advance(base + 45 * day); // the clock is inside b; a was missed entirely
    expect(data.map((row: { action: string }) => row.action)).toEqual(["ended", "activated", "ended", "activated"]);
    const after = await statuses();
    expect(after.get(realActive.id)).toBe("ended");
    expect(after.get(a.id)).toBe("ended");
    expect(after.get(b.id)).toBe("active");
    expect(await activeCount()).toBe(1);
  }, 60000);

  it("a season is carried through all three states: upcoming → active → ended", async () => {
    const base = Date.parse(realActive.end_at);
    const first = await newSeason("life1", base, base + 30 * day);
    const second = await newSeason("life2", base + 30 * day, base + 60 * day);
    const seen: string[] = [(await statuses()).get(first.id)!];
    expect((await transition(first.id, "active")).error).toBeNull();
    seen.push((await statuses()).get(first.id)!);
    expect((await advance(base + 31 * day)).error).toBeNull(); // first's end has passed and second is due
    seen.push((await statuses()).get(first.id)!);
    expect(seen).toEqual(["upcoming", "active", "ended"]);
    expect((await statuses()).get(second.id)).toBe("active");
    expect(await activeCount()).toBe(1);
  }, 60000);

  it("the lifecycle functions are not callable by the public anon key", async () => {
    const { createClient } = await import("@supabase/supabase-js");
    const anon = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    const attempt = await anon.rpc("advance_seasons", { p_now: iso(Date.now()) });
    expect(attempt.error).not.toBeNull();
    const attempt2 = await anon.rpc("transition_season", { p_season: realActive.id, p_to: "ended" });
    expect(attempt2.error).not.toBeNull();
  }, 60000);
});
