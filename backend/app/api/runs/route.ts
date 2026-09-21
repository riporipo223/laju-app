import { NextResponse } from "next/server";
import { resolveRunStatus } from "@/lib/anti-cheat/status-resolution";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { type GPSPoint, haversineMeters } from "@/lib/gps-geometry";
import { calculatePoints } from "@/lib/point-calculation";
import { MAX_BODY_BYTES, MAX_ROUTE_POINTS } from "@/lib/rate-limit";
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
  const result = await requireUser(request, "runs.post");
  if (isAuthFailure(result)) return result.response;
  const { user } = result;

  // SEC-10 (T2.20a): bound what one request may cost BEFORE parsing or any anti-cheat work. `content-length` is
  // checked first so an oversized body is refused without being read; the point count below covers a body
  // that arrives without one. 413 is a permanent rejection to the client (SyncService never resends it).
  const declaredBytes = Number(request.headers.get("content-length") ?? 0);
  if (declaredBytes > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Request body too large" }, { status: 413 });
  }

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
  // `run.duration_seconds` is an integer column, but the client measures a real elapsed time (Core Data `Double`, e.g.
  // 236.83) — found by the first end-to-end run from the actual app: the raw value made the insert fail, every real
  // run got a 500 and stayed queued forever. Round at the boundary, so the contract is "any positive number of seconds".
  const durationSeconds = Math.round(duration_seconds);
  if (durationSeconds < 1) {
    return NextResponse.json({ error: "duration_seconds must be at least 1 second" }, { status: 400 });
  }

  if (Array.isArray(gps_route) && gps_route.length > MAX_ROUTE_POINTS) {
    return NextResponse.json({ error: `gps_route may hold at most ${MAX_ROUTE_POINTS} points` }, { status: 413 });
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

  const avgPaceSecPerKm = Math.round(durationSeconds / (distance_meters / 1000));
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
      duration_seconds: durationSeconds,
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

const RECONCILIATION_DEFAULT_LOOKBACK_MS = 90 * 24 * 60 * 60 * 1000; // 90 days
const RECONCILIATION_PAGE_SIZE = 200;

interface ReconciliationRunRow {
  id: string;
  status: string;
  flag_confidence: string | null;
  final_points_awarded: number;
  resolved_at: string | null;
  updated_at: string;
  anomaly_flags: string[];
}

/**
 * T2.14c: database-api-spec.md §2.2b — lets the client learn about a `flagged` run's *later* resolution
 * (LOW auto-approves up to `REVIEW_WINDOW_LOW` after submission, HIGH resolves at an arbitrary later time
 * via manual override, tech-spec.md §2.4.1). Filters on `updated_at`, never `resolved_at` — `resolved_at`
 * stays null for any still-`flagged` run, so a `resolved_at`-based filter would never surface the
 * transition *into* `flagged` at all, only the later resolution out of it. `updated_at` is touched by
 * T2.2's own DB trigger on every status/flag_confidence/final_points_awarded/resolved_at change, so
 * nothing is missed.
 *
 * `since` omitted → `now() - 90 days` (the only legal way to seed a client's first-ever call — a device
 * timestamp is explicitly forbidden here, same reasoning as `duration_seconds` staying client-asserted
 * elsewhere: the client has no trustworthy timestamp of its own before this endpoint hands it one via
 * `server_time`). `since` present but unparseable → `400`, never for a missing one.
 *
 * Result capped at `RECONCILIATION_PAGE_SIZE` (200), ordered `updated_at` ASC (oldest-changed-first) — the
 * spec's own note on why DESC + `server_time`-cursor is wrong: it would advance the window past whatever's
 * still undrained, permanently skipping it. ASC + "persist the last row's updated_at as the next since" is
 * the only direction that can't lose data. Fetches `PAGE_SIZE + 1` rows to detect `has_more` without a
 * separate COUNT query, then trims back to `PAGE_SIZE`.
 */
export async function GET(request: Request) {
  const result = await requireUser(request, "runs.get");
  if (isAuthFailure(result)) return result.response;
  const { user } = result;

  const url = new URL(request.url);
  const sinceParam = url.searchParams.get("since");

  let since: Date;
  if (sinceParam === null) {
    since = new Date(Date.now() - RECONCILIATION_DEFAULT_LOOKBACK_MS);
  } else {
    const parsed = new Date(sinceParam);
    if (Number.isNaN(parsed.getTime())) {
      return NextResponse.json({ error: "since must be a valid ISO 8601 timestamp" }, { status: 400 });
    }
    since = parsed;
  }

  const { data, error } = await supabaseAdmin
    .from("run")
    .select("id, status, flag_confidence, final_points_awarded, resolved_at, updated_at, anomaly_flags")
    .eq("user_id", user.id)
    .gte("updated_at", since.toISOString())
    .order("updated_at", { ascending: true })
    .limit(RECONCILIATION_PAGE_SIZE + 1);

  if (error) {
    return NextResponse.json({ error: "Could not load runs" }, { status: 500 });
  }

  const rows = (data ?? []) as ReconciliationRunRow[];
  const hasMore = rows.length > RECONCILIATION_PAGE_SIZE;
  const page = hasMore ? rows.slice(0, RECONCILIATION_PAGE_SIZE) : rows;

  return NextResponse.json({
    server_time: new Date().toISOString(),
    has_more: hasMore,
    runs: page.map((row) => ({
      run_id: row.id,
      status: row.status,
      flag_confidence: row.flag_confidence,
      final_points_awarded: row.final_points_awarded,
      resolved_at: row.resolved_at,
      updated_at: row.updated_at,
      anomaly_flags: row.anomaly_flags,
    })),
  });
}
