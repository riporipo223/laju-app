import { describe, expect, it } from "vitest";
import { isPremiumClub } from "./premium";

describe("isPremiumClub stub (TODO(T4.20))", () => {
  it("denies every club until the real Premium check ships", async () => {
    for (const clubId of ["club-1", "club-2", "", "00000000-0000-0000-0000-000000000000"]) {
      expect(await isPremiumClub(clubId)).toBe(false);
    }
  });
});
