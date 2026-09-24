/**
 * STUB: always denies until T4.20 ships.
 * TODO(T4.20): replace with the real Premium check — "is this club's OWNER's subscription active?"
 * (product-spec.md §4.19 Premium Club, §4.23 decided #9/#10: Apple status 1/3/4 = Premium, read live
 * from the App Store Server API at the moment of the action).
 *
 * Deliberately returns `false` for every club, with no environment flag, no test hook and no bypass:
 * a "temporarily always true" stub is exactly the kind of thing that ships to production by accident.
 * Until this is replaced, no Club War can be created or activated — that is the intended state.
 */
export async function isPremiumClub(clubId: string): Promise<boolean> {
  void clubId;
  return false;
}

export type PremiumChecker = (clubId: string) => Promise<boolean>;
