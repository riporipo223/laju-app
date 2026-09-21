import { describe, expect, it } from "vitest";
import { isStreakQualifying, localDayNumber, priorStreakDays, STREAK_LOOKBACK_DAYS } from "./streak";

/** Asia/Jakarta noon of a given local day (day 0 = the day `base` falls on). */
const base = new Date("2026-09-21T05:00:00Z"); // 12:00 WIB on 21 Sep
const dayOffset = (days: number) => new Date(base.getTime() + days * 86_400_000);

describe("priorStreakDays — same semantics as the client's StreakTracker (consecutive days ending yesterday)", () => {
  it("is 0 with no history", () => {
    expect(priorStreakDays([], base)).toBe(0);
  });

  it("counts consecutive prior days", () => {
    expect(priorStreakDays([dayOffset(-1)], base)).toBe(1);
    expect(priorStreakDays([dayOffset(-1), dayOffset(-2), dayOffset(-3)], base)).toBe(3);
  });

  it("a missed day resets it: a run two days ago without one yesterday is no streak", () => {
    expect(priorStreakDays([dayOffset(-2), dayOffset(-3)], base)).toBe(0);
  });

  it("stops at the first gap rather than looking past it", () => {
    expect(priorStreakDays([dayOffset(-1), dayOffset(-2), dayOffset(-4)], base)).toBe(2);
  });

  it("counts a day once however many runs it held", () => {
    expect(priorStreakDays([dayOffset(-1), new Date(dayOffset(-1).getTime() + 3_600_000), dayOffset(-2)], base)).toBe(2);
  });

  it("ignores runs on the same day as the one being scored, and later ones", () => {
    expect(priorStreakDays([dayOffset(0), dayOffset(1)], base)).toBe(0);
  });

  it("is capped at the lookback the bonus can use (7 days)", () => {
    const twelve = Array.from({ length: 12 }, (_, i) => dayOffset(-(i + 1)));
    expect(priorStreakDays(twelve, base)).toBe(STREAK_LOOKBACK_DAYS);
  });
});

describe("day boundaries are Asia/Jakarta, not UTC", () => {
  it("23:30 UTC is already the next calendar day in WIB", () => {
    const lateUtc = new Date("2026-09-20T23:30:00Z"); // 06:30 WIB on 21 Sep
    expect(localDayNumber(lateUtc)).toBe(localDayNumber(new Date("2026-09-21T05:00:00Z")));
    // …so a run at 06:30 WIB on the 21st has "yesterday" = the 20th, not the 19th.
    expect(priorStreakDays([new Date("2026-09-20T05:00:00Z")], lateUtc)).toBe(1);
  });

  it("16:59 UTC is still the same WIB day; 17:00 UTC is midnight and starts the next", () => {
    expect(localDayNumber(new Date("2026-09-21T16:59:00Z"))).not.toBe(localDayNumber(new Date("2026-09-21T17:00:00Z")));
  });
});

describe("isStreakQualifying — the anti-grinding distance gate", () => {
  it("needs at least 100 m", () => {
    expect(isStreakQualifying(99.9)).toBe(false);
    expect(isStreakQualifying(100)).toBe(true);
  });
});
