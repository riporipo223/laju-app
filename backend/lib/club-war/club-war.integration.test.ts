/**
 * Migration 20260923200000_club_war_schema.sql (`club`, `club_member`, `club_war`, `club_war_club`,
 * `club_war_participant`) applied to production 2026-09-24 — this file no longer expects to fail.
 *
 * Skips only when there are no real credentials (the repo-wide integration pattern).
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { ClubBusyError } from "./repository";

const hasRealCredentials = Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);

describe.skipIf(!hasRealCredentials)("Club War repository against the real schema", () => {
  const tag = `cw-it-${Date.now()}`;
  const created = { users: [] as string[], clubs: [] as string[], wars: [] as string[] };
  let supabaseAdmin: typeof import("@/lib/supabase").supabaseAdmin;
  let repo: typeof import("./supabase-repository").supabaseClubWarRepository;
  const club = (i: number): string => {
    const id = created.clubs[i];
    if (!id) throw new Error(`club ${i} was not created`);
    return id;
  };
  const user = (i: number): string => {
    const id = created.users[i];
    if (!id) throw new Error(`user ${i} was not created`);
    return id;
  };

  beforeAll(async () => {
    ({ supabaseAdmin } = await import("@/lib/supabase"));
    ({ supabaseClubWarRepository: repo } = await import("./supabase-repository"));

    for (const name of ["a-owner", "a-member", "b-owner"]) {
      const { data, error } = await supabaseAdmin.from("user").insert({ username: `${tag}-${name}` }).select("id").single();
      if (error) throw error;
      created.users.push(data.id);
    }
    for (const name of ["A", "B", "C", "D"]) {
      const { data, error } = await supabaseAdmin.from("club").insert({ name: `${tag}-${name}` }).select("id").single();
      if (error) throw error;
      created.clubs.push(data.id);
    }
    const { error } = await supabaseAdmin.from("club_member").insert([
      { user_id: user(0), club_id: club(0), role: "owner" },
      { user_id: user(1), club_id: club(0), role: "member" },
      { user_id: user(2), club_id: club(1), role: "owner" },
    ]);
    if (error) throw error;
  });

  afterAll(async () => {
    if (!supabaseAdmin) return;
    await supabaseAdmin.from("club_war_participant").delete().in("club_war_id", created.wars);
    await supabaseAdmin.from("club_war_club").delete().in("club_war_id", created.wars);
    await supabaseAdmin.from("club_war").delete().in("id", created.wars);
    await supabaseAdmin.from("club_member").delete().in("user_id", created.users);
    await supabaseAdmin.from("club").delete().in("id", created.clubs);
    await supabaseAdmin.from("user").delete().in("id", created.users);
  });

  it("reads membership from club_member", async () => {
    expect(await repo.getMembership(user(0))).toEqual({ clubId: club(0), role: "owner" });
    expect(await repo.getMembership("00000000-0000-0000-0000-000000000000")).toBeNull();
  });

  it("creates a pending war, activates it once, snapshots, and records a result", async () => {
    const [clubA, clubB] = [club(0), club(1)];
    const now = new Date();
    const warId = await repo.createWar({
      inviterClubId: clubA,
      invitedClubIds: [clubB],
      sentAt: now,
      deadline: new Date(now.getTime() + 24 * 3600 * 1000),
    });
    created.wars.push(warId);

    const pending = await repo.getWar(warId);
    expect(pending?.status).toBe("pending");
    // The inviter's acceptance time is its send time — AC5's final tie-break reads it.
    expect(pending?.clubs.find((c) => c.role === "inviter")?.respondedAt?.getTime()).toBe(now.getTime());
    expect(await repo.clubsInOpenWar([clubA, clubB, club(2)])).toEqual(expect.arrayContaining([clubA, clubB]));
    expect(await repo.clubsInOpenWar([club(2)])).toEqual([]);
    expect(pending?.clubs.map((c) => [c.clubId, c.role, c.inviteStatus]).sort()).toEqual(
      [
        [clubA, "inviter", "accepted"],
        [clubB, "invited", "pending"],
      ].sort()
    );

    await repo.setInviteStatus(warId, clubB, "accepted", now);
    expect(await repo.activateWar(warId, now)).toBe(true);
    expect(await repo.activateWar(warId, now)).toBe(false);

    await repo.insertParticipants(warId, await repo.listMembers([clubA, clubB]), now);
    expect((await repo.listParticipants(warId)).length).toBe(3);

    expect(
      await repo.recordResult(warId, now, {
        winnerClubId: clubA,
        winReason: "participation_rate",
        clubs: [
          { clubId: clubA, participationRate: 0.5, outcome: "win" },
          { clubId: clubB, participationRate: 0, outcome: "loss" },
        ],
      })
    ).toBe(true);
    expect((await repo.getWar(warId))?.status).toBe("ended");
    expect((await repo.listWarsForClub(clubB)).map((w) => w.id)).toContain(warId);
  });

  it("a declined challenge dissolves exactly once", async () => {
    const [clubA, clubB] = [club(0), club(1)];
    const now = new Date();
    const warId = await repo.createWar({ inviterClubId: clubA, invitedClubIds: [clubB], sentAt: now, deadline: now });
    created.wars.push(warId);
    expect(await repo.dissolveWar(warId)).toBe(true);
    expect(await repo.dissolveWar(warId)).toBe(false);
    expect(await repo.listExpiredPendingWarIds(new Date())).not.toContain(warId);
  });

  it("the database refuses a fourth club in one war (T4.2a trigger, §4.19 AC1)", async () => {
    const [clubA, clubB, clubC, clubD] = [club(0), club(1), club(2), club(3)];
    const now = new Date();
    const warId = await repo.createWar({ inviterClubId: clubA, invitedClubIds: [clubB, clubC], sentAt: now, deadline: now });
    created.wars.push(warId);
    const { error } = await supabaseAdmin
      .from("club_war_club")
      .insert({ club_war_id: warId, club_id: clubD, role: "invited", invite_status: "pending" });
    expect(error?.message).toMatch(/already has 3 clubs/);
    expect(await repo.dissolveWar(warId)).toBe(true);
  });

  it("the database refuses a club a second open war (T4.2a trigger, §4.19 AC14)", async () => {
    const [clubA, clubB, clubC] = [club(0), club(1), club(2)];
    const now = new Date();
    const warId = await repo.createWar({ inviterClubId: clubA, invitedClubIds: [clubB], sentAt: now, deadline: now });
    created.wars.push(warId);
    await expect(
      repo.createWar({ inviterClubId: clubC, invitedClubIds: [clubB], sentAt: now, deadline: now })
    ).rejects.toBeInstanceOf(ClubBusyError);
    expect(await repo.dissolveWar(warId)).toBe(true);
  });

  it("the database stores win_reason 'forfeit_premium_lapse' (T4.2a CHECK, amended 2026-09-24)", async () => {
    const [clubA, clubB] = [club(0), club(1)];
    const now = new Date();
    const warId = await repo.createWar({ inviterClubId: clubA, invitedClubIds: [clubB], sentAt: now, deadline: now });
    created.wars.push(warId);
    await repo.activateWar(warId, now);
    const { error } = await supabaseAdmin
      .from("club_war")
      .update({ status: "ended", winner_club_id: clubB, win_reason: "forfeit_premium_lapse" })
      .eq("id", warId);
    expect(error).toBeNull();
  });
});
