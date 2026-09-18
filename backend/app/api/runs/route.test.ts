import { beforeEach, describe, expect, it, vi } from "vitest";

const requireUserMock = vi.fn();
const insertChain = {
  select: vi.fn(() => insertChain),
  single: vi.fn(),
};
const insertMock = vi.fn((_row: unknown) => insertChain);
// findExistingRun's select().eq().eq().maybeSingle() chain — defaults to "not found" (null) so tests that
// don't care about duplicate-detection can ignore it entirely.
interface ExistingRunData {
  id: string;
  status: string;
  flag_confidence: string | null;
  final_points_awarded: number;
  resolved_at: string | null;
  anomaly_flags: string[];
}
const selectChain = {
  select: vi.fn(() => selectChain),
  eq: vi.fn(() => selectChain),
  maybeSingle: vi.fn(
    (): Promise<{ data: ExistingRunData | null; error: { code: string; message: string } | null }> =>
      Promise.resolve({ data: null, error: null })
  ),
};
const trustMultiplierForUserMock = vi.fn();
const recomputeAndPersistTrustScoreMock = vi.fn();
const resolveRunStatusMock = vi.fn();
const recordRunPointsAndUpdateAggregateMock = vi.fn();
// Fixed 1km per segment regardless of actual coordinates — real haversine correctness is covered by
// gps-geometry's own callers (pace-cap.test.ts etc.), not this route's orchestration tests.
const haversineMetersMock = vi.fn((..._args: unknown[]) => 1000);

vi.mock("@/lib/auth", () => ({
  isAuthFailure: (result: unknown) => typeof result === "object" && result !== null && "response" in result,
  requireUser: (...args: unknown[]) => requireUserMock(...args),
}));

vi.mock("@/lib/supabase", () => ({
  supabaseAdmin: { from: () => ({ insert: insertMock, select: selectChain.select }) },
}));

vi.mock("@/lib/trust-score", () => ({
  trustMultiplierForUser: (...args: unknown[]) => trustMultiplierForUserMock(...args),
  recomputeAndPersistTrustScore: (...args: unknown[]) => recomputeAndPersistTrustScoreMock(...args),
}));

vi.mock("@/lib/anti-cheat/status-resolution", () => ({
  resolveRunStatus: (...args: unknown[]) => resolveRunStatusMock(...args),
}));

vi.mock("@/lib/point-transaction", () => ({
  recordRunPointsAndUpdateAggregate: (...args: unknown[]) => recordRunPointsAndUpdateAggregateMock(...args),
}));

vi.mock("@/lib/gps-geometry", () => ({
  haversineMeters: (...args: unknown[]) => haversineMetersMock(...args),
}));

const { POST } = await import("./route");

const completeUser = {
  id: "usr-1",
  auth_user_id: "auth-1",
  deleted_at: null,
  region_kecamatan: "Cilandak",
  region_kabupaten_kota: "Jakarta Selatan",
  region_provinsi: "DKI Jakarta",
};

const validPoint = { lat: -6.2, lng: 106.8, timestamp: "2026-09-08T06:00:01Z", elevation: 45.2 };
// 3 points = 2 segments, so validSegmentsDistanceKm with the mocked 1km/segment haversine is predictable.
const twoSegmentRoute = [
  { lat: -6.2, lng: 106.8, timestamp: "2026-09-08T06:00:01Z", elevation: 45.2 },
  { lat: -6.201, lng: 106.801, timestamp: "2026-09-08T06:00:11Z", elevation: 45.5 },
  { lat: -6.202, lng: 106.802, timestamp: "2026-09-08T06:00:21Z", elevation: 45.8 },
];

function request(body: unknown) {
  return new Request("https://example.com/api/runs", {
    method: "POST",
    headers: { authorization: "Bearer valid-jwt", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function validated() {
  return { status: "validated" as const, flagConfidence: null, excludedSegmentIndices: [], anomalyFlags: [], excludedPct: 0 };
}

describe("POST /api/runs", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects unauthenticated requests", async () => {
    requireUserMock.mockResolvedValueOnce({ response: Response.json({}, { status: 401 }) });
    const res = await POST(request({}));
    expect(res.status).toBe(401);
    expect(insertMock).not.toHaveBeenCalled();
  });

  it("returns 400 for zero/negative distance_meters", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(
      request({ distance_meters: 0, duration_seconds: 100, gps_route: [validPoint] })
    );
    expect(res.status).toBe(400);
  });

  it("returns 400 for zero/negative duration_seconds", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(
      request({ distance_meters: 100, duration_seconds: -5, gps_route: [validPoint] })
    );
    expect(res.status).toBe(400);
  });

  it("returns 422 for a gps_route point missing elevation", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(
      request({
        distance_meters: 100,
        duration_seconds: 60,
        gps_route: [{ lat: -6.2, lng: 106.8, timestamp: "2026-09-08T06:00:01Z" }],
      })
    );
    expect(res.status).toBe(422);
  });

  it("returns 422 for an empty gps_route", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    const res = await POST(request({ distance_meters: 100, duration_seconds: 60, gps_route: [] }));
    expect(res.status).toBe(422);
  });

  it("returns 409 when the user has no region set", async () => {
    requireUserMock.mockResolvedValueOnce({
      user: { ...completeUser, region_kecamatan: null },
    });
    const res = await POST(
      request({ distance_meters: 100, duration_seconds: 60, gps_route: [validPoint] })
    );
    expect(res.status).toBe(409);
  });

  it("creates a validated run using resolveRunStatus's decision, full points, trust_multiplier applied", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    resolveRunStatusMock.mockReturnValueOnce(validated());
    trustMultiplierForUserMock.mockResolvedValueOnce(1.0);
    recomputeAndPersistTrustScoreMock.mockResolvedValueOnce(1.0);
    recordRunPointsAndUpdateAggregateMock.mockResolvedValueOnce({ totalPoints: 2, currentLevel: 1 });
    insertChain.single.mockResolvedValueOnce({ data: { id: "run_456" }, error: null });
    const res = await POST(
      request({
        started_at: "2026-09-08T06:00:00Z",
        ended_at: "2026-09-08T06:32:10Z",
        distance_meters: 10000,
        duration_seconds: 3600, // avg_pace=360s/km -> pace bracket [240,420)=1.0x
        gps_route: twoSegmentRoute,
      })
    );
    expect(res.status).toBe(201);
    const json = await res.json();
    expect(json.run_id).toBe("run_456");
    expect(json.status).toBe("validated");
    expect(json.flag_confidence).toBeNull();
    expect(json.anomaly_flags).toEqual([]);
    expect(json.resolved_at).not.toBeNull();
    // no exclusions -> validDistanceKm = 2 segments * 1km (mocked) = 2km -> raw=2*1.0=2 -> *trust(1.0)=2
    expect(json.final_points_awarded).toBe(2);
    expect(recordRunPointsAndUpdateAggregateMock).toHaveBeenCalledWith("usr-1", "run_456", 2);
    expect(recomputeAndPersistTrustScoreMock).toHaveBeenCalledWith("usr-1");
  });

  it("applies trust_multiplier < 1.0 to reduce final_points_awarded — T2.11", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    resolveRunStatusMock.mockReturnValueOnce(validated());
    trustMultiplierForUserMock.mockResolvedValueOnce(0.9);
    recomputeAndPersistTrustScoreMock.mockResolvedValueOnce(0.9);
    recordRunPointsAndUpdateAggregateMock.mockResolvedValueOnce({ totalPoints: 2, currentLevel: 1 });
    insertChain.single.mockResolvedValueOnce({ data: { id: "run_789" }, error: null });
    const res = await POST(
      request({ distance_meters: 10000, duration_seconds: 3600, gps_route: twoSegmentRoute })
    );
    const json = await res.json();
    // raw=2 * trust=0.9 = 1.8 -> round = 2
    expect(json.final_points_awarded).toBe(2);

    const insertedRow = insertMock.mock.calls.at(-1)?.[0] as { estimated_points: number };
    expect(insertedRow.estimated_points).toBe(2);
  });

  it("a flagged run: status/flag_confidence come from resolveRunStatus, resolved_at is null, points use only valid segments", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    resolveRunStatusMock.mockReturnValueOnce({
      status: "flagged",
      flagConfidence: "low",
      excludedSegmentIndices: [0], // segment 0 excluded, segment 1 valid
      anomalyFlags: ["pace_cap_exceeded"],
      excludedPct: 50,
    });
    trustMultiplierForUserMock.mockResolvedValueOnce(1.0);
    recomputeAndPersistTrustScoreMock.mockResolvedValueOnce(1.0);
    recordRunPointsAndUpdateAggregateMock.mockResolvedValueOnce({ totalPoints: 1, currentLevel: 1 });
    insertChain.single.mockResolvedValueOnce({ data: { id: "run_flagged" }, error: null });
    const res = await POST(
      request({ distance_meters: 10000, duration_seconds: 3600, gps_route: twoSegmentRoute })
    );
    expect(res.status).toBe(201);
    const json = await res.json();
    expect(json.status).toBe("flagged");
    expect(json.flag_confidence).toBe("low");
    expect(json.anomaly_flags).toEqual(["pace_cap_exceeded"]);
    expect(json.resolved_at).toBeNull();
    // only segment 1 is valid -> 1km -> raw=1*1.0=1 -> *trust(1.0)=1 (NOT the full 2km/2 points)
    expect(json.final_points_awarded).toBe(1);
    // flagged runs DO get a PointTransaction — partial points, per tech-spec.md §2.4.1 ("bukan 0, bukan full")
    expect(recordRunPointsAndUpdateAggregateMock).toHaveBeenCalledWith("usr-1", "run_flagged", 1);

    const insertedRow = insertMock.mock.calls.at(-1)?.[0] as {
      status: string;
      flag_confidence: string;
      resolved_at: string | null;
    };
    expect(insertedRow.status).toBe("flagged");
    expect(insertedRow.flag_confidence).toBe("low");
    expect(insertedRow.resolved_at).toBeNull();
  });

  it("a rejected run: final_points_awarded is 0 and trust_multiplier is never queried", async () => {
    requireUserMock.mockResolvedValueOnce({ user: completeUser });
    resolveRunStatusMock.mockReturnValueOnce({
      status: "rejected",
      flagConfidence: null,
      excludedSegmentIndices: [0, 1],
      anomalyFlags: ["gps_speed_jump_segment_0", "gps_speed_jump_segment_1"],
      excludedPct: 100,
    });
    recomputeAndPersistTrustScoreMock.mockResolvedValueOnce(1.0);
    insertChain.single.mockResolvedValueOnce({ data: { id: "run_rejected" }, error: null });
    const res = await POST(
      request({ distance_meters: 10000, duration_seconds: 3600, gps_route: twoSegmentRoute })
    );
    expect(res.status).toBe(201);
    const json = await res.json();
    expect(json.status).toBe("rejected");
    expect(json.final_points_awarded).toBe(0);
    expect(json.resolved_at).not.toBeNull();
    expect(trustMultiplierForUserMock).not.toHaveBeenCalled();
    // T2.12c DoD: no PointTransaction ever written for an immediate rejected run.
    expect(recordRunPointsAndUpdateAggregateMock).not.toHaveBeenCalled();

    const insertedRow = insertMock.mock.calls.at(-1)?.[0] as {
      final_points_awarded: number;
      estimated_points: number;
    };
    expect(insertedRow.final_points_awarded).toBe(0);
    expect(insertedRow.estimated_points).toBe(0);
  });

  describe("T2.12d — duplicate submission idempotency", () => {
    it("a duplicate (same user_id+started_at) returns the existing result without re-running the pipeline", async () => {
      requireUserMock.mockResolvedValueOnce({ user: completeUser });
      selectChain.maybeSingle.mockResolvedValueOnce({
        data: {
          id: "run_existing",
          status: "validated",
          flag_confidence: null,
          final_points_awarded: 7,
          resolved_at: "2026-09-08T06:32:15Z",
          anomaly_flags: [],
        },
        error: null,
      });
      const res = await POST(
        request({
          started_at: "2026-09-08T06:00:00Z",
          distance_meters: 10000,
          duration_seconds: 3600,
          gps_route: twoSegmentRoute,
        })
      );
      expect(res.status).toBe(200);
      const json = await res.json();
      expect(json).toEqual({
        run_id: "run_existing",
        status: "validated",
        flag_confidence: null,
        final_points_awarded: 7,
        resolved_at: "2026-09-08T06:32:15Z",
        anomaly_flags: [],
      });
      expect(resolveRunStatusMock).not.toHaveBeenCalled();
      expect(insertMock).not.toHaveBeenCalled();
      expect(recordRunPointsAndUpdateAggregateMock).not.toHaveBeenCalled();
      expect(recomputeAndPersistTrustScoreMock).not.toHaveBeenCalled();
    });

    it("a concurrent duplicate (DB unique-constraint race, code 23505) returns the winner's result, not a 500", async () => {
      requireUserMock.mockResolvedValueOnce({ user: completeUser });
      resolveRunStatusMock.mockReturnValueOnce(validated());
      trustMultiplierForUserMock.mockResolvedValueOnce(1.0);
      // First lookup (early check): not found yet — this request proceeds to insert.
      selectChain.maybeSingle.mockResolvedValueOnce({ data: null, error: null });
      // Insert loses the race: another concurrent request already committed the same (user_id, started_at).
      insertChain.single.mockResolvedValueOnce({
        data: null,
        error: { code: "23505", message: "duplicate key value violates unique constraint" },
      });
      // Recovery lookup: the winner's row is now visible.
      selectChain.maybeSingle.mockResolvedValueOnce({
        data: {
          id: "run_winner",
          status: "validated",
          flag_confidence: null,
          final_points_awarded: 5,
          resolved_at: "2026-09-08T06:32:15Z",
          anomaly_flags: [],
        },
        error: null,
      });

      const res = await POST(
        request({
          started_at: "2026-09-08T06:00:00Z",
          distance_meters: 10000,
          duration_seconds: 3600,
          gps_route: twoSegmentRoute,
        })
      );
      expect(res.status).toBe(200);
      const json = await res.json();
      expect(json.run_id).toBe("run_winner");
      expect(json.final_points_awarded).toBe(5);
      // This request lost the race — it must not write a second PointTransaction or recompute trust twice.
      expect(recordRunPointsAndUpdateAggregateMock).not.toHaveBeenCalled();
      expect(recomputeAndPersistTrustScoreMock).not.toHaveBeenCalled();
    });
  });
});
