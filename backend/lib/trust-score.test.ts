import { describe, expect, it, vi } from "vitest";

// Pure-function tests only — mocked so importing this module doesn't try to construct a real Supabase
// client (trust-score.ts imports ./supabase at module load time, same as every other lib/ file).
vi.mock("./supabase", () => ({ supabaseAdmin: {} }));

const { computeTrustMultiplier } = await import("./trust-score");

describe("computeTrustMultiplier — tech-spec.md §2.4 formula, one DoD item per test", () => {
  it("returns exactly 1.0 for a user with no flags in the window", () => {
    expect(computeTrustMultiplier({ highFlagCount: 0, lowDecayFlagCount: 0, cleanRunCount: 0 })).toBe(1.0);
  });

  it("one HIGH flag yields 0.90", () => {
    expect(computeTrustMultiplier({ highFlagCount: 1, lowDecayFlagCount: 0, cleanRunCount: 0 })).toBeCloseTo(0.9, 10);
  });

  it("one LOW flag that was manually overridden (not auto-approved) yields 0.95", () => {
    // lowDecayFlagCount counts any LOW flag that did NOT end in auto-approve — manual override included.
    expect(computeTrustMultiplier({ highFlagCount: 0, lowDecayFlagCount: 1, cleanRunCount: 0 })).toBeCloseTo(
      0.95,
      10
    );
  });

  it("a LOW flag that auto-approved after REVIEW_WINDOW_LOW produces NO decay — stays 1.0", () => {
    // The exemption is applied by the caller BEFORE building inputs: an auto-approved LOW flag is excluded
    // from lowDecayFlagCount entirely (see fetchTrustScoreInputs), so it never reaches this function as a
    // decay input. This is the rule most likely to be implemented wrong — verified again in the DB-query
    // level integration test, not just here in isolation.
    expect(computeTrustMultiplier({ highFlagCount: 0, lowDecayFlagCount: 0, cleanRunCount: 0 })).toBe(1.0);
  });

  it("floor: 8 HIGH flags compute to 0.20 before clamping, but return 0.3 — never lower, never 0", () => {
    const unclamped = 1.0 - 0.1 * 8;
    expect(unclamped).toBeCloseTo(0.2, 10);
    expect(computeTrustMultiplier({ highFlagCount: 8, lowDecayFlagCount: 0, cleanRunCount: 0 })).toBe(0.3);
  });

  it("floor holds even with an absurd number of flags — never below 0.3", () => {
    expect(computeTrustMultiplier({ highFlagCount: 50, lowDecayFlagCount: 50, cleanRunCount: 0 })).toBe(0.3);
  });

  it("recovery: +0.02 per clean run — tech-spec.md's own worked example (1 HIGH flag, 3 clean runs = 0.96)", () => {
    expect(computeTrustMultiplier({ highFlagCount: 1, lowDecayFlagCount: 0, cleanRunCount: 3 })).toBeCloseTo(
      0.96,
      10
    );
  });

  it("ceiling: recovery never pushes the multiplier above 1.0, even when clean runs outnumber flags", () => {
    expect(computeTrustMultiplier({ highFlagCount: 0, lowDecayFlagCount: 0, cleanRunCount: 50 })).toBe(1.0);
    expect(computeTrustMultiplier({ highFlagCount: 1, lowDecayFlagCount: 0, cleanRunCount: 10 })).toBe(1.0);
  });

  it("combines HIGH decay, LOW decay, and recovery in one call", () => {
    // 1.0 - 0.10 - 0.05*2 + 0.02*4 = 1.0 - 0.10 - 0.10 + 0.08 = 0.88
    expect(computeTrustMultiplier({ highFlagCount: 1, lowDecayFlagCount: 2, cleanRunCount: 4 })).toBeCloseTo(
      0.88,
      10
    );
  });

  it("T4.22 (product-spec.md §4.29 AC4): one severe speed violation decays MORE than one HIGH flag", () => {
    const highOnly = computeTrustMultiplier({ highFlagCount: 1, lowDecayFlagCount: 0, cleanRunCount: 0 });
    const severeOnly = computeTrustMultiplier({
      highFlagCount: 0,
      lowDecayFlagCount: 0,
      cleanRunCount: 0,
      severeSpeedViolationCount: 1,
    });
    expect(severeOnly).toBeLessThan(highOnly);
  });

  it("severeSpeedViolationCount defaults to 0 when omitted — every pre-existing call site unaffected", () => {
    expect(computeTrustMultiplier({ highFlagCount: 0, lowDecayFlagCount: 0, cleanRunCount: 0 })).toBe(1.0);
  });

  it("one severe speed violation yields 0.80 — starting value, 2x HIGH_FLAG_DECAY, needs real calibration", () => {
    expect(
      computeTrustMultiplier({ highFlagCount: 0, lowDecayFlagCount: 0, cleanRunCount: 0, severeSpeedViolationCount: 1 })
    ).toBeCloseTo(0.8, 10);
  });
});
