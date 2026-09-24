import { describe, expect, it } from "vitest";
import { createChallenge, expirePendingChallenges, finalizeDueWars, respondToChallenge, type Deps } from "./lifecycle";
import { isPremiumClub } from "./premium";
import type { ClubWarRepository } from "./repository";
import { ACCEPT_WINDOW_MS, WAR_DURATION_MS } from "./scoring";
import type { ClubRole, Participant, RunRecord, War, WarResult } from "./types";

// In-memory stand-in for T4.2a's tables. Transitions are conditional, like the Supabase implementation.
class InMemoryRepo implements ClubWarRepository {
  members = new Map<string, { clubId: string; role: ClubRole }>();
  clubs = new Set<string>();
  wars = new Map<string, War>();
  participants = new Map<string, Participant[]>();
  runs: RunRecord[] = [];
  results = new Map<string, WarResult>();
  private seq = 0;

  async getMembership(userId: string) {
    return this.members.get(userId) ?? null;
  }
  async existingClubIds(ids: string[]) {
    return ids.filter((id) => this.clubs.has(id));
  }
  async createWar(input: { inviterClubId: string; invitedClubIds: string[]; sentAt: Date; deadline: Date }) {
    const id = `war-${++this.seq}`;
    this.wars.set(id, {
      id,
      status: "pending",
      challengeSentAt: input.sentAt,
      acceptDeadlineAt: input.deadline,
      startedAt: null,
      endedAt: null,
      winnerClubId: null,
      winReason: null,
      clubs: [
        { clubId: input.inviterClubId, role: "inviter", inviteStatus: "accepted" },
        ...input.invitedClubIds.map((clubId) => ({ clubId, role: "invited" as const, inviteStatus: "pending" as const })),
      ],
    });
    return id;
  }
  async getWar(id: string) {
    const war = this.wars.get(id);
    return war ? structuredClone(war) : null;
  }
  async setInviteStatus(warId: string, clubId: string, status: "pending" | "accepted" | "declined") {
    const entry = this.wars.get(warId)?.clubs.find((c) => c.clubId === clubId && c.inviteStatus === "pending");
    if (entry) entry.inviteStatus = status;
  }
  async dissolveWar(warId: string) {
    const war = this.wars.get(warId);
    if (war?.status !== "pending") return false;
    war.status = "dissolved";
    return true;
  }
  async activateWar(warId: string, startedAt: Date) {
    const war = this.wars.get(warId);
    if (war?.status !== "pending") return false;
    war.status = "active";
    war.startedAt = startedAt;
    return true;
  }
  async listMembers(clubIds: string[]) {
    return [...this.members.entries()]
      .filter(([, m]) => clubIds.includes(m.clubId))
      .map(([userId, m]) => ({ userId, clubId: m.clubId }));
  }
  async insertParticipants(warId: string, rows: Participant[]) {
    this.participants.set(warId, rows);
  }
  async listExpiredPendingWarIds(now: Date) {
    return [...this.wars.values()]
      .filter((w) => w.status === "pending" && w.acceptDeadlineAt.getTime() <= now.getTime())
      .map((w) => w.id);
  }
  async listActiveWarsStartedBefore(cutoff: Date) {
    return [...this.wars.values()].filter(
      (w) => w.status === "active" && w.startedAt !== null && w.startedAt.getTime() <= cutoff.getTime()
    );
  }
  async listParticipants(warId: string) {
    return this.participants.get(warId) ?? [];
  }
  async listRuns(userIds: string[], from: Date, to: Date) {
    return this.runs.filter(
      (r) => userIds.includes(r.userId) && r.startedAt >= from && r.startedAt < to
    );
  }
  async recordResult(warId: string, endedAt: Date, result: WarResult) {
    const war = this.wars.get(warId);
    if (war?.status !== "active") return false;
    war.status = "ended";
    war.endedAt = endedAt;
    war.winnerClubId = result.winnerClubId;
    war.winReason = result.winReason;
    this.results.set(warId, result);
    return true;
  }
  async listWarsForClub(clubId: string) {
    return [...this.wars.values()].filter((w) => w.clubs.some((c) => c.clubId === clubId));
  }
}

const T0 = new Date("2026-10-01T00:00:00Z");

/**
 * Premium is injected, never globally bypassed: production wiring (`http.ts`) always uses the real
 * always-deny stub. Tests that need the success path grant Premium to named clubs only.
 */
function setup(premiumClubs: string[] = []) {
  const repo = new InMemoryRepo();
  let now = T0;
  const deps: Deps = {
    repo,
    isPremiumClub: async (clubId) => premiumClubs.includes(clubId),
    now: () => now,
  };
  for (const c of ["A", "B", "C", "D"]) repo.clubs.add(c);
  repo.members.set("ownerA", { clubId: "A", role: "owner" });
  repo.members.set("adminB", { clubId: "B", role: "admin" });
  repo.members.set("ownerC", { clubId: "C", role: "owner" });
  repo.members.set("memberA", { clubId: "A", role: "member" });
  repo.members.set("memberB", { clubId: "B", role: "member" });
  return { repo, deps, advance: (ms: number) => (now = new Date(now.getTime() + ms)) };
}

describe("createChallenge", () => {
  it("with the real stub, every challenge is refused as not_premium_club", async () => {
    const { deps, repo } = setup();
    const result = await createChallenge({ ...deps, isPremiumClub }, { callerUserId: "ownerA", invitedClubIds: ["B"] });
    expect(result).toEqual({ ok: false, error: "not_premium_club" });
    expect(repo.wars.size).toBe(0);
  });

  it("creates a pending war with a 24h accept deadline for a Premium Club's owner", async () => {
    const { deps, repo } = setup(["A"]);
    const result = await createChallenge(deps, { callerUserId: "ownerA", invitedClubIds: ["B", "C"] });
    expect(result.ok).toBe(true);
    const war = [...repo.wars.values()][0];
    if (!war) throw new Error("expected a war to be created");
    expect(war.status).toBe("pending");
    expect(war.acceptDeadlineAt.getTime() - T0.getTime()).toBe(ACCEPT_WINDOW_MS);
    expect(war.clubs.map((c) => [c.clubId, c.role, c.inviteStatus])).toEqual([
      ["A", "inviter", "accepted"],
      ["B", "invited", "pending"],
      ["C", "invited", "pending"],
    ]);
  });

  it.each([
    [[], "invalid_request"],
    [["B", "C", "D"], "invalid_request"],
    [["B", "B"], "invalid_request"],
    ["B", "invalid_request"],
    [[42], "invalid_request"],
    [["A"], "cannot_challenge_own_club"],
    [["nope"], "club_not_found"],
  ])("rejects invited_club_ids %j with %s", async (ids, error) => {
    const { deps } = setup(["A"]);
    expect(await createChallenge(deps, { callerUserId: "ownerA", invitedClubIds: ids })).toEqual({ ok: false, error });
  });

  it("requires club membership and an owner/admin role", async () => {
    const { deps } = setup(["A"]);
    expect(await createChallenge(deps, { callerUserId: "stranger", invitedClubIds: ["B"] })).toEqual({
      ok: false,
      error: "not_in_club",
    });
    expect(await createChallenge(deps, { callerUserId: "memberA", invitedClubIds: ["B"] })).toEqual({
      ok: false,
      error: "not_club_admin",
    });
  });
});

async function pendingWar(premium: string[], invited: string[]) {
  const ctx = setup(premium);
  const created = await createChallenge(ctx.deps, { callerUserId: "ownerA", invitedClubIds: invited });
  if (!created.ok) throw new Error(created.error);
  return { ...ctx, warId: created.value.warId };
}

describe("respondToChallenge", () => {
  it("a decline dissolves the challenge — no result recorded for anyone (AC7)", async () => {
    const { deps, repo, warId } = await pendingWar(["A"], ["B"]);
    const result = await respondToChallenge(deps, { callerUserId: "adminB", warId, accept: false });
    expect(result).toEqual({ ok: true, value: { status: "dissolved" } });
    expect(repo.wars.get(warId)?.status).toBe("dissolved");
    expect(repo.results.size).toBe(0);
  });

  it("answering after the 24h deadline dissolves instead of accepting (AC7)", async () => {
    const { deps, repo, warId, advance } = await pendingWar(["A"], ["B"]);
    advance(ACCEPT_WINDOW_MS);
    const result = await respondToChallenge(deps, { callerUserId: "adminB", warId, accept: true });
    expect(result).toEqual({ ok: true, value: { status: "dissolved" } });
    expect(repo.wars.get(warId)?.status).toBe("dissolved");
  });

  it("stays pending until every invited club accepts, then activates and freezes the roster (AC2, AC11)", async () => {
    const { deps, repo, warId } = await pendingWar(["A"], ["B", "C"]);
    expect(await respondToChallenge(deps, { callerUserId: "adminB", warId, accept: true })).toEqual({
      ok: true,
      value: { status: "pending" },
    });
    expect(await respondToChallenge(deps, { callerUserId: "ownerC", warId, accept: true })).toEqual({
      ok: true,
      value: { status: "active" },
    });
    expect(repo.wars.get(warId)?.startedAt).toEqual(T0);
    const snapshot = repo.participants.get(warId)?.map((p) => p.userId).sort();
    expect(snapshot).toEqual(["adminB", "memberA", "memberB", "ownerA", "ownerC"]);
  });

  it("the inviter losing Premium before the last accept dissolves it — no record (AC12)", async () => {
    const { deps, repo, warId } = await pendingWar(["A"], ["B"]);
    const result = await respondToChallenge({ ...deps, isPremiumClub }, { callerUserId: "adminB", warId, accept: true });
    expect(result).toEqual({ ok: true, value: { status: "dissolved" } });
    expect(repo.results.size).toBe(0);
  });

  it("only an owner/admin of an invited club can respond", async () => {
    const { deps, warId } = await pendingWar(["A"], ["B"]);
    expect(await respondToChallenge(deps, { callerUserId: "ownerA", warId, accept: true })).toEqual({
      ok: false,
      error: "not_invited",
    });
    expect(await respondToChallenge(deps, { callerUserId: "memberB", warId, accept: true })).toEqual({
      ok: false,
      error: "not_club_admin",
    });
    expect(await respondToChallenge(deps, { callerUserId: "adminB", warId: "missing", accept: true })).toEqual({
      ok: false,
      error: "war_not_found",
    });
    expect(await respondToChallenge(deps, { callerUserId: "adminB", warId, accept: "yes" })).toEqual({
      ok: false,
      error: "invalid_request",
    });
  });

  it("can't respond twice or to a war that is no longer pending", async () => {
    const { deps, warId } = await pendingWar(["A"], ["B", "C"]);
    await respondToChallenge(deps, { callerUserId: "adminB", warId, accept: true });
    expect(await respondToChallenge(deps, { callerUserId: "adminB", warId, accept: true })).toEqual({
      ok: false,
      error: "already_responded",
    });
    await respondToChallenge(deps, { callerUserId: "ownerC", warId, accept: false });
    expect(await respondToChallenge(deps, { callerUserId: "adminB", warId, accept: false })).toEqual({
      ok: false,
      error: "war_not_pending",
    });
  });
});

describe("expirePendingChallenges", () => {
  it("dissolves only challenges past their deadline", async () => {
    const { deps, repo, warId, advance } = await pendingWar(["A"], ["B"]);
    expect(await expirePendingChallenges(deps)).toEqual([]);
    advance(ACCEPT_WINDOW_MS);
    expect(await expirePendingChallenges(deps)).toEqual([warId]);
    expect(repo.wars.get(warId)?.status).toBe("dissolved");
    expect(repo.results.size).toBe(0);
  });
});

describe("finalizeDueWars", () => {
  async function activeWar(premium: string[]) {
    const ctx = await pendingWar(premium, ["B"]);
    await respondToChallenge(ctx.deps, { callerUserId: "adminB", warId: ctx.warId, accept: true });
    return ctx;
  }
  const runAt = (userId: string, offsetMs: number, distanceMeters = 5000): RunRecord => ({
    userId,
    startedAt: new Date(T0.getTime() + offsetMs),
    distanceMeters,
    status: "validated",
    finalPointsAwarded: 5,
  });

  it("does nothing before the 48h mark", async () => {
    const { deps, advance } = await activeWar(["A"]);
    advance(WAR_DURATION_MS - 1);
    expect(await finalizeDueWars(deps)).toEqual({ ended: [], unresolvedTies: [] });
  });

  it("records the participation-rate winner at 48h", async () => {
    const { deps, repo, warId, advance } = await activeWar(["A"]);
    repo.runs.push(runAt("ownerA", 1000), runAt("memberA", 2000), runAt("adminB", 3000));
    advance(WAR_DURATION_MS);
    expect(await finalizeDueWars(deps)).toEqual({ ended: [warId], unresolvedTies: [] });
    const war = repo.wars.get(warId)!;
    expect(war).toMatchObject({ status: "ended", winnerClubId: "A", winReason: "participation_rate" });
    expect(repo.results.get(warId)?.clubs).toEqual([
      { clubId: "A", participationRate: 1, outcome: "win" },
      { clubId: "B", participationRate: 0.5, outcome: "loss" },
    ]);
  });

  it("uses the frozen snapshot: someone who joined after activation doesn't count (AC11)", async () => {
    const { deps, repo, warId, advance } = await activeWar(["A"]);
    repo.members.set("lateB", { clubId: "B", role: "member" });
    repo.runs.push(runAt("ownerA", 1000), runAt("adminB", 1000), runAt("memberB", 1000), runAt("lateB", 1000));
    advance(WAR_DURATION_MS);
    await finalizeDueWars(deps);
    expect(repo.results.get(warId)?.clubs.find((c) => c.clubId === "B")?.participationRate).toBe(1);
  });

  it("forfeits the inviter if its owner's Premium lapsed during the war (AC10)", async () => {
    const { deps, repo, warId, advance } = await activeWar(["A"]);
    repo.runs.push(runAt("ownerA", 1000), runAt("memberA", 1000), runAt("adminB", 1000));
    advance(WAR_DURATION_MS);
    await finalizeDueWars({ ...deps, isPremiumClub });
    expect(repo.wars.get(warId)).toMatchObject({ winnerClubId: "B", winReason: "forfeit_premium_lapse" });
  });

  it("leaves a fully tied war active and reports it instead of inventing a winner", async () => {
    const { deps, repo, warId, advance } = await activeWar(["A"]);
    repo.runs.push(runAt("ownerA", 1000), runAt("memberA", 1000), runAt("adminB", 1000), runAt("memberB", 1000));
    advance(WAR_DURATION_MS);
    expect(await finalizeDueWars(deps)).toEqual({ ended: [], unresolvedTies: [warId] });
    expect(repo.wars.get(warId)?.status).toBe("active");
  });

  it("ignores runs outside the window and rejected runs", async () => {
    const { deps, repo, warId, advance } = await activeWar(["A"]);
    repo.runs.push(
      runAt("ownerA", 1000),
      runAt("adminB", -1),
      runAt("memberB", WAR_DURATION_MS),
      { ...runAt("memberB", 1000), status: "rejected" }
    );
    advance(WAR_DURATION_MS);
    await finalizeDueWars(deps);
    expect(repo.wars.get(warId)).toMatchObject({ winnerClubId: "A", winReason: "forfeit_inactivity" });
  });
});
