// Club War domain types (product-spec.md §4.19). Shapes mirror T4.2a's schema
// (supabase/migrations/20260923200000_club_war_schema.sql), which is written but NOT applied yet.

export type ClubRole = "owner" | "admin" | "member";
export type WarStatus = "pending" | "active" | "dissolved" | "ended";
export type WarClubRole = "inviter" | "invited";
export type InviteStatus = "pending" | "accepted" | "declined";
export type Outcome = "win" | "loss";

// `forfeit_premium_lapse` is NOT in T4.2a's `club_war.win_reason` CHECK yet — see the T4.2b report.
export type WinReason = "participation_rate" | "tie_break" | "forfeit_inactivity" | "forfeit_premium_lapse";

export type RunStatus = "validated" | "flagged" | "approved" | "rejected";

export interface Membership {
  clubId: string;
  role: ClubRole;
}

export interface WarClub {
  clubId: string;
  role: WarClubRole;
  inviteStatus: InviteStatus;
}

export interface War {
  id: string;
  status: WarStatus;
  challengeSentAt: Date;
  acceptDeadlineAt: Date;
  startedAt: Date | null;
  endedAt: Date | null;
  winnerClubId: string | null;
  winReason: WinReason | null;
  clubs: WarClub[];
}

export interface Participant {
  userId: string;
  clubId: string;
}

export interface RunRecord {
  userId: string;
  startedAt: Date;
  distanceMeters: number;
  status: RunStatus;
  finalPointsAwarded: number | null;
}

export interface ClubResult {
  clubId: string;
  participationRate: number;
  outcome: Outcome;
}

export interface WarResult {
  winnerClubId: string | null;
  winReason: WinReason | null;
  clubs: ClubResult[];
}
