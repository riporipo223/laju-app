/**
 * STUB: always denies until T4.20 ships.
 * TODO(T4.20): replace with the real Premium check — "does this user have an active subscription?"
 * (product-spec.md §4.19/§4.23 decided #9/#10: Apple status 1/3/4 = Premium, read live from the App
 * Store Server API at the moment of the action, or the most recent `subscription` row for this user).
 *
 * Deliberately returns `false` for every user, with no environment flag, no test hook and no bypass —
 * same shape as `lib/club-war/premium.ts`'s `isPremiumClub`, and the same reasoning: a "temporarily
 * always true" stub is exactly the kind of thing that ships to production by accident. Until this is
 * replaced, no club can be created by anyone — that is the intended state (phase-4-backlog.md T4.1,
 * reversed 2026-09-25: Create Club now requires Premium).
 */
export async function isPremiumUser(userId: string): Promise<boolean> {
  void userId;
  return false;
}

export type UserPremiumChecker = (userId: string) => Promise<boolean>;
