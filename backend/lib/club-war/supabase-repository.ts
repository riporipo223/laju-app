import { supabaseAdmin } from "@/lib/supabase";
import { ClubBusyError, type ClubWarRepository } from "./repository";
import type { ClubRole, InviteStatus, Participant, RunRecord, RunStatus, War, WarClubRole, WarStatus, WinReason } from "./types";

// Written against T4.2a's schema (20260923200000_club_war_schema.sql), which is NOT applied yet —
// every call here fails against the live database until it is.

interface WarRow {
  id: string;
  status: WarStatus;
  challenge_sent_at: string;
  accept_deadline_at: string;
  started_at: string | null;
  ended_at: string | null;
  winner_club_id: string | null;
  win_reason: WinReason | null;
  club_war_club: { club_id: string; role: WarClubRole; invite_status: InviteStatus; responded_at: string | null }[];
}

const WAR_SELECT =
  "id, status, challenge_sent_at, accept_deadline_at, started_at, ended_at, winner_club_id, win_reason, club_war_club(club_id, role, invite_status, responded_at)";

function toWar(row: WarRow): War {
  const date = (value: string | null) => (value ? new Date(value) : null);
  return {
    id: row.id,
    status: row.status,
    challengeSentAt: new Date(row.challenge_sent_at),
    acceptDeadlineAt: new Date(row.accept_deadline_at),
    startedAt: date(row.started_at),
    endedAt: date(row.ended_at),
    winnerClubId: row.winner_club_id,
    winReason: row.win_reason,
    clubs: row.club_war_club.map((c) => ({
      clubId: c.club_id,
      role: c.role,
      inviteStatus: c.invite_status,
      respondedAt: date(c.responded_at),
    })),
  };
}

function check(error: { message: string } | null, what: string): void {
  if (error) throw new Error(`Club War ${what} failed: ${error.message}`);
}

// Raised by T4.2a's `club_war_club_enforce_one_open_war` trigger (§4.19 AC14).
const ONE_OPEN_WAR_MESSAGE = "already in a pending or active war";

export const supabaseClubWarRepository: ClubWarRepository = {
  async getMembership(userId) {
    const { data, error } = await supabaseAdmin
      .from("club_member")
      .select("club_id, role")
      .eq("user_id", userId)
      .maybeSingle<{ club_id: string; role: ClubRole }>();
    check(error, "membership lookup");
    return data ? { clubId: data.club_id, role: data.role } : null;
  },

  async existingClubIds(clubIds) {
    const { data, error } = await supabaseAdmin.from("club").select("id").in("id", clubIds);
    check(error, "club lookup");
    return (data ?? []).map((row: { id: string }) => row.id);
  },

  async clubsInOpenWar(clubIds) {
    const { data, error } = await supabaseAdmin
      .from("club_war_club")
      .select("club_id, club_war!inner(status)")
      .in("club_id", clubIds)
      .in("club_war.status", ["pending", "active"]);
    check(error, "open war lookup");
    return [...new Set((data ?? []).map((row: { club_id: string }) => row.club_id))];
  },

  async createWar({ inviterClubId, invitedClubIds, sentAt, deadline }) {
    const { data, error } = await supabaseAdmin
      .from("club_war")
      .insert({ status: "pending", challenge_sent_at: sentAt.toISOString(), accept_deadline_at: deadline.toISOString() })
      .select("id")
      .single<{ id: string }>();
    check(error, "war insert");
    const warId = data!.id;

    const rows = [
      // The inviter "accepts" by sending — its responded_at is AC5's acceptance time for the final tie-break.
      { club_war_id: warId, club_id: inviterClubId, role: "inviter", invite_status: "accepted", responded_at: sentAt.toISOString() },
      ...invitedClubIds.map((clubId) => ({ club_war_id: warId, club_id: clubId, role: "invited", invite_status: "pending" })),
    ];
    const { error: clubsError } = await supabaseAdmin.from("club_war_club").insert(rows);
    if (clubsError) {
      // No transaction across the two inserts: remove the half-created war rather than leave an orphan.
      await supabaseAdmin.from("club_war").delete().eq("id", warId);
      if (clubsError.message.includes(ONE_OPEN_WAR_MESSAGE)) throw new ClubBusyError(clubsError.message);
      check(clubsError, "war clubs insert");
    }
    return warId;
  },

  async getWar(warId) {
    const { data, error } = await supabaseAdmin.from("club_war").select(WAR_SELECT).eq("id", warId).maybeSingle<WarRow>();
    check(error, "war lookup");
    return data ? toWar(data) : null;
  },

  async setInviteStatus(warId, clubId, status, at) {
    const { error } = await supabaseAdmin
      .from("club_war_club")
      .update({ invite_status: status, responded_at: at.toISOString() })
      .eq("club_war_id", warId)
      .eq("club_id", clubId)
      .eq("invite_status", "pending");
    check(error, "invite update");
  },

  async dissolveWar(warId) {
    const { data, error } = await supabaseAdmin
      .from("club_war")
      .update({ status: "dissolved" })
      .eq("id", warId)
      .eq("status", "pending")
      .select("id");
    check(error, "dissolve");
    return (data ?? []).length > 0;
  },

  async activateWar(warId, startedAt) {
    const { data, error } = await supabaseAdmin
      .from("club_war")
      .update({ status: "active", started_at: startedAt.toISOString() })
      .eq("id", warId)
      .eq("status", "pending")
      .select("id");
    check(error, "activate");
    return (data ?? []).length > 0;
  },

  async listMembers(clubIds) {
    const { data, error } = await supabaseAdmin.from("club_member").select("user_id, club_id").in("club_id", clubIds);
    check(error, "member list");
    return (data ?? []).map((row: { user_id: string; club_id: string }) => ({ userId: row.user_id, clubId: row.club_id }));
  },

  async insertParticipants(warId, participants: Participant[], at) {
    if (participants.length === 0) return;
    const { error } = await supabaseAdmin.from("club_war_participant").insert(
      participants.map((p) => ({ club_war_id: warId, club_id: p.clubId, user_id: p.userId, snapshotted_at: at.toISOString() }))
    );
    check(error, "participant snapshot");
  },

  async listExpiredPendingWarIds(now) {
    const { data, error } = await supabaseAdmin
      .from("club_war")
      .select("id")
      .eq("status", "pending")
      .lte("accept_deadline_at", now.toISOString());
    check(error, "expired lookup");
    return (data ?? []).map((row: { id: string }) => row.id);
  },

  async listActiveWarsStartedBefore(cutoff) {
    const { data, error } = await supabaseAdmin
      .from("club_war")
      .select(WAR_SELECT)
      .eq("status", "active")
      .lte("started_at", cutoff.toISOString());
    check(error, "due wars lookup");
    return ((data ?? []) as WarRow[]).map(toWar);
  },

  async listParticipants(warId) {
    const { data, error } = await supabaseAdmin
      .from("club_war_participant")
      .select("user_id, club_id")
      .eq("club_war_id", warId);
    check(error, "participant list");
    return (data ?? []).map((row: { user_id: string; club_id: string }) => ({ userId: row.user_id, clubId: row.club_id }));
  },

  async listRuns(userIds, from, to) {
    if (userIds.length === 0) return [];
    const { data, error } = await supabaseAdmin
      .from("run")
      .select("user_id, started_at, distance_meters, status, final_points_awarded")
      .in("user_id", userIds)
      .gte("started_at", from.toISOString())
      .lt("started_at", to.toISOString());
    check(error, "run lookup");
    return (data ?? []).map(
      (row: { user_id: string; started_at: string; distance_meters: number | null; status: RunStatus; final_points_awarded: number | null }): RunRecord => ({
        userId: row.user_id,
        startedAt: new Date(row.started_at),
        distanceMeters: row.distance_meters ?? 0,
        status: row.status,
        finalPointsAwarded: row.final_points_awarded,
      })
    );
  },

  async recordResult(warId, endedAt, result) {
    const { data, error } = await supabaseAdmin
      .from("club_war")
      .update({
        status: "ended",
        ended_at: endedAt.toISOString(),
        winner_club_id: result.winnerClubId,
        win_reason: result.winReason,
      })
      .eq("id", warId)
      .eq("status", "active")
      .select("id");
    check(error, "result");
    if ((data ?? []).length === 0) return false;

    for (const club of result.clubs) {
      const { error: clubError } = await supabaseAdmin
        .from("club_war_club")
        .update({ participation_rate: club.participationRate, outcome: club.outcome })
        .eq("club_war_id", warId)
        .eq("club_id", club.clubId);
      check(clubError, "club result");
    }
    return true;
  },

  async listWarsForClub(clubId) {
    const { data: ids, error: idsError } = await supabaseAdmin
      .from("club_war_club")
      .select("club_war_id")
      .eq("club_id", clubId);
    check(idsError, "club wars lookup");
    const warIds = (ids ?? []).map((row: { club_war_id: string }) => row.club_war_id);
    if (warIds.length === 0) return [];
    const { data, error } = await supabaseAdmin
      .from("club_war")
      .select(WAR_SELECT)
      .in("id", warIds)
      .order("challenge_sent_at", { ascending: false });
    check(error, "club wars");
    return ((data ?? []) as WarRow[]).map(toWar);
  },
};
