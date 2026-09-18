import { NextResponse } from "next/server";
import { resolveRunStatus } from "@/lib/anti-cheat/status-resolution";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { type GPSPoint, haversineMeters } from "@/lib/gps-geometry";
import { calculatePoints } from "@/lib/point-calculation";
import { recordRunPointsAndUpdateAggregate } from "@/lib/point-transaction";
import { supabaseAdmin } from "@/lib/supabase";
import { recomputeAndPersistTrustScore, trustMultiplierForUser } from "@/lib/trust-score";

interface GPSPointInput {
  lat?: unknown;
  lng?: unknown;
  timestamp?: unknown;
  elevation?: unknown;
}

interface RunBody {
  started_at?: unknown;
  ended_at?: unknown;
  distance_meters?: unknown;
  duration_seconds?: unknown;
  gps_route?: unknown;
}

function isValidPoint(point: unknown): point is GPSPoint {
  if (typeof point !== "object" || point === null) return false;
  const p = point as GPSPointInput;
  return (
    typeof p.lat === "number" &&
    typeof p.lng === "number" &&
    typeof p.timestamp === "string" &&
    typeof p.elevation === "number"
  );
}

/** Sum of haversine distances for segments NOT excluded by any anti-cheat check, in km. */
function validSegmentsDistanceKm(route: GPSPoint[], excludedSegmentIndices: number[]): number {
  const excluded = new Set(excludedSegmentIndices);
  let meters = 0;
  for (let i = 0; i < route.length - 1; i++) {
    if (excluded.has(i)) continue;
    meters += haversineMeters(route[i]!, route[i + 1]!);
  }
  return meters / 1000;
}

interface ExistingRunRow {
  id: string;
  status: string;
  flag_confidence: string | null;
  final_points_awarded: number;
  resolved_at: string | null;
  anomaly_flags: string[];
}

/** T2.12d: looks up a run already submitted for this (user_id, started_at) pair. */
async function findExistingRun(userId: string, startedAt: string): Promise<ExistingRunRow | null> {
  const { data, error } = await supabaseAdmin
    .from("run")
    .select("id, status, flag_confidence, final_points_awarded, resolved_at, anomaly_flags")
    .eq("user_id", userId)
    .eq("started_at", startedAt)
    .maybeSingle<ExistingRunRow>();

  if (error) {
    throw new Error(`Could not look up existing run: ${error.message}`);
  }
  return data;
}

function existingRunResponse(run: ExistingRunRow) {
  return NextResponse.json(
    {
      run_id: run.id,
      status: run.status,
      flag_confidence: run.flag_confidence,
      final_points_awarded: run.final_points_awarded,
      resolved_at: run.resolved_at,
      anomaly_flags: run.anomaly_flags,
    },
    { status: 200 }
  );
}

/**
 * T2.5: database-api-spec.md §2.2 — ingestion. T2.12a wires T2.6-T2.11's outputs into the aggregate
 * `validated`/`flagged`/`rejected` decision (tech-spec.md §2.4.1) via `resolveRunStatus` — the anti-cheat
 * checks (T2.7-T2.10) themselves never decide status, only exclusions/flags (Round 2 finding B-5).
 * `PointTransaction`/ledger writes and `User` aggregate updates are T2.12c's job.
 *
 * T2.12d: a duplicate submission (same `user_id`+`started_at`, from the mobile sync queue's retry logic)
 * never re-runs the pipeline or writes a second `PointTransaction` — returns the existing run's result
 * instead. Two enforcement layers: an early lookup (`findExistingRun`, cheap, handles the common sequential-
 * retry case) and the DB's own `run_user_id_started_at_key` unique constraint as the actual race-condition
 * backstop (concurrent duplicate submissions can both pass the early lookup before either has inserted;
 * only the DB constraint — not any amount of application-level locking — can guarantee exactly one wins).
 *
 * Points are computed from valid (non-excluded) segments only, per tech-spec.md §2.4.1's own wording for
 * BOTH `validated` ("Poin penuh... dikurangi segmen exclude kalau ada") and `flagged` ("Poin dari segmen
 * valid saja... bukan 0, bukan full") — the same formula, just a possibly-reduced distance input. An
 * immediate `rejected` run gets `final_points_awarded = 0` (no ledger entry is ever written for it, tech-
 * spec.md §2.4.1), and skips the trust-multiplier query entirely since 0 × anything is still 0.
 *
 * `raw_points` uses `streakDays = 0` — server-side streak tracking (T1.1's client-side `priorStreakDays`
 * has no backend equivalent yet) was never in scope for T2.6, T2.11, or this task.
 *
 * Uses `requireUser` (not `requireAuthenticatedIdentity`, unlike T2.4) — this endpoint needs the caller's
 * region fields already on the resolved row to check the 409 guard below, and by definition a run can only
 * be submitted by an identity that already completed T2.4's profile step.
 */
export async function POST(request: Request) {
  const result = await requireUser(request);
  if (isAuthFailure(result)) return result.response;
  const { user } = result;

  let body: RunBody;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { started_at, ended_at, distance_meters, duration_seconds, gps_route } = body;

  if (typeof distance_meters !== "number" || distance_meters <= 0) {
    return NextResponse.json({ error: "distance_meters must be a positive number" }, { status: 400 });
  }
  if (typeof duration_seconds !== "number" || duration_seconds <= 0) {
    return NextResponse.json({ error: "duration_seconds must be a positive number" }, { status: 400 });
  }

  if (!Array.isArray(gps_route) || gps_route.length === 0 || !gps_route.every(isValidPoint)) {
    return NextResponse.json(
      { error: "gps_route must be a non-empty array of {lat, lng, timestamp, elevation} points" },
      { status: 422 }
    );
  }

  // Presence-only guard (database-api-spec.md §3) — the richer client-side onboarding block that
  // prevents reaching this call at all is T3.1's job, not this task's.
  if (!user.region_kecamatan || !user.region_kabupaten_kota || !user.region_provinsi) {
    return NextResponse.json({ error: "Region must be set before submitting a run" }, { status: 409 });
  }

  // T2.12d: a retried submission (mobile sync queue, T2.14) must never re-run the pipeline or write a
  // second PointTransaction. This early lookup handles the common sequential-retry case cheaply; the
  // actual race-condition backstop is the DB unique constraint caught further below.
  const startedAtKey = typeof started_at === "string" ? started_at : null;
  if (startedAtKey !== null) {
    const existing = await findExistingRun(user.id, startedAtKey);
    if (existing) {
      return existingRunResponse(existing);
    }
  }

  const avgPaceSecPerKm = Math.round(duration_seconds / (distance_meters / 1000));
  // Only `validated`/`flagged` ever get a resolved_at at submission time — a still-flagged run's
  // resolved_at stays null until T2.12b resolves it (tech-spec.md §2.4.1); immediate-rejected resolves now.
  const submittedAt = new Date().toISOString();

  const resolution = resolveRunStatus(gps_route);

  let finalPointsAwarded = 0;
  let estimatedPoints = 0;
  if (resolution.status !== "rejected") {
    const trustMultiplier = await trustMultiplierForUser(user.id);
    const validDistanceKm = validSegmentsDistanceKm(gps_route, resolution.excludedSegmentIndices);
    const rawPoints = calculatePoints(validDistanceKm, avgPaceSecPerKm, 0);
    estimatedPoints = Math.round(rawPoints);
    finalPointsAwarded = Math.round(rawPoints * trustMultiplier);
  }

  const { data: run, error } = await supabaseAdmin
    .from("run")
    .insert({
      user_id: user.id,
      started_at: typeof started_at === "string" ? started_at : null,
      ended_at: typeof ended_at === "string" ? ended_at : null,
      distance_meters,
      duration_seconds,
      avg_pace_sec_per_km: avgPaceSecPerKm,
      gps_route,
      status: resolution.status,
      flag_confidence: resolution.flagConfidence,
      anomaly_flags: resolution.anomalyFlags,
      estimated_points: estimatedPoints,
      final_points_awarded: finalPointsAwarded,
      resolved_at: resolution.status === "flagged" ? null : submittedAt,
    })
    .select("id")
    .single();

  if (error) {
    // T2.12d: postgres unique_violation (23505) on run_user_id_started_at_key means a concurrent duplicate
    // submission won the race and inserted first — return ITS already-committed result instead of erroring,
    // and skip ledger/trust-score work below entirely, since this request didn't actually create anything.
    if (error.code === "23505" && startedAtKey !== null) {
      const existing = await findExistingRun(user.id, startedAtKey);
      if (existing) {
        return existingRunResponse(existing);
      }
    }
    return NextResponse.json({ error: "Could not save run" }, { status: 500 });
  }
  if (!run) {
    return NextResponse.json({ error: "Could not save run" }, { status: 500 });
  }

  // T2.12c: PointTransaction ledger write + User.total_points/current_level aggregate update. Never called
  // for `rejected` — tech-spec.md §2.4.1: "no PointTransaction ever written" for an immediate rejection.
  if (resolution.status !== "rejected") {
    try {
      await recordRunPointsAndUpdateAggregate(user.id, run.id, finalPointsAwarded);
    } catch (ledgerError) {
      return NextResponse.json(
        { error: ledgerError instanceof Error ? ledgerError.message : "Could not record PointTransaction" },
        { status: 500 }
      );
    }
  }

  // T2.11 DoD: trust_score recomputed on each validated run, generalized here to every submission — a new
  // HIGH/LOW flag decays the score the moment it's flagged (tech-spec.md §2.4: "setiap flag HIGH selalu
  // dihitung"), not only once resolved, and an immediate-rejected run is trust-neutral either way (no
  // flag_confidence is ever set on it). The second recompute trigger — a flag resolving later — is
  // T2.12b's job, not this one's.
  await recomputeAndPersistTrustScore(user.id);

  return NextResponse.json(
    {
      run_id: run.id,
      status: resolution.status,
      flag_confidence: resolution.flagConfidence,
      final_points_awarded: finalPointsAwarded,
      resolved_at: resolution.status === "flagged" ? null : submittedAt,
      anomaly_flags: resolution.anomalyFlags,
    },
    { status: 201 }
  );
}
