import type { InviteStatus, Membership, Participant, RunRecord, War, WarResult } from "./types";

/**
 * Storage boundary for Club War. `lifecycle.ts` depends only on this, so its rules are unit-testable
 * with an in-memory fake; `supabase-repository.ts` is the real implementation against T4.2a's schema.
 *
 * Conditional transitions (`dissolveWar`, `activateWar`, `recordResult`) only succeed from the
 * expected status and report whether they did — two concurrent callers can't both win a transition.
 */
/** Thrown by `createWar` when the database's one-open-war trigger (T4.2a, §4.19 AC14) refuses a club. */
export class ClubBusyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ClubBusyError";
  }
}

export interface ClubWarRepository {
  getMembership(userId: string): Promise<Membership | null>;
  existingClubIds(clubIds: string[]): Promise<string[]>;
  /** Of `clubIds`, those already in a pending or active war (§4.19 AC14). */
  clubsInOpenWar(clubIds: string[]): Promise<string[]>;
  createWar(input: { inviterClubId: string; invitedClubIds: string[]; sentAt: Date; deadline: Date }): Promise<string>;
  getWar(warId: string): Promise<War | null>;
  setInviteStatus(warId: string, clubId: string, status: InviteStatus, at: Date): Promise<void>;
  dissolveWar(warId: string): Promise<boolean>;
  activateWar(warId: string, startedAt: Date): Promise<boolean>;
  listMembers(clubIds: string[]): Promise<Participant[]>;
  insertParticipants(warId: string, participants: Participant[], at: Date): Promise<void>;
  listExpiredPendingWarIds(now: Date): Promise<string[]>;
  listActiveWarsStartedBefore(cutoff: Date): Promise<War[]>;
  listParticipants(warId: string): Promise<Participant[]>;
  listRuns(userIds: string[], from: Date, to: Date): Promise<RunRecord[]>;
  recordResult(warId: string, endedAt: Date, result: WarResult): Promise<boolean>;
  listWarsForClub(clubId: string): Promise<War[]>;
}
