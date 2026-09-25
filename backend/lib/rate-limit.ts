import { NextResponse } from "next/server";
import { supabaseAdmin } from "./supabase";

/**
 * T2.20a (SEC-9). Fixed-window limits backed by `rate_limit_hit` (migration 20260921120000) — atomic in Postgres,
 * shared by every serverless instance. Two layers, wired into the auth helpers in `lib/auth.ts` so no route can
 * forget the IP layer:
 *  - per IP, BEFORE any auth call (an unauthenticated flood otherwise costs one Supabase Auth request per call);
 *  - per user, right after the caller is identified, using the route's rule below.
 *
 * Every number here is a STARTING value, sized against the measured ceiling of ≈25 `POST /api/runs`/s (T2.12e)
 * and the fact that a device offline for weeks legitimately uploads a backlog (the test device holds 127 runs).
 */
export interface RateLimitWindow {
  windowSeconds: number;
  limit: number;
}

export const RATE_LIMIT_RULES = {
  "runs.post": [
    { windowSeconds: 60, limit: 30 },
    { windowSeconds: 3600, limit: 300 },
  ],
  "runs.get": [{ windowSeconds: 3600, limit: 30 }],
  "leaderboard.get": [{ windowSeconds: 60, limit: 60 }],
  "progress.get": [{ windowSeconds: 60, limit: 60 }],
  "seasons.active": [{ windowSeconds: 60, limit: 60 }],
  "seasons.history": [{ windowSeconds: 60, limit: 60 }],
  "auth.me": [{ windowSeconds: 60, limit: 60 }],
  "profile.complete": [{ windowSeconds: 3600, limit: 10 }],
  "account.delete": [{ windowSeconds: 3600, limit: 3 }],
  "clubwar.create": [{ windowSeconds: 3600, limit: 20 }],
  "clubwar.respond": [{ windowSeconds: 3600, limit: 30 }],
  "clubwar.get": [{ windowSeconds: 60, limit: 60 }],
  "social.post.create": [{ windowSeconds: 3600, limit: 30 }],
  "social.post.list": [{ windowSeconds: 60, limit: 60 }],
  "social.post.delete": [{ windowSeconds: 3600, limit: 30 }],
  "social.post.like": [{ windowSeconds: 60, limit: 60 }],
  "gear.create": [{ windowSeconds: 3600, limit: 30 }],
  "gear.list": [{ windowSeconds: 60, limit: 60 }],
} as const satisfies Record<string, readonly RateLimitWindow[]>;

export type RateLimitRule = keyof typeof RATE_LIMIT_RULES;

/** Coarse per-IP ceiling across every `/api/*` route. */
export const IP_RATE_LIMIT: RateLimitWindow = { windowSeconds: 60, limit: 120 };

/** The client address as set by the platform's edge. `null` when there is none (direct calls, tests). */
export function clientIp(request: Request): string | null {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || request.headers.get("x-real-ip")?.trim() || null;
}

export function rateLimitedResponse(retryAfterSeconds: number): NextResponse {
  return NextResponse.json(
    { error: "rate_limited", retry_after_seconds: retryAfterSeconds },
    { status: 429, headers: { "Retry-After": String(retryAfterSeconds) } }
  );
}

export interface HitResult {
  allowed: boolean;
  retryAfterSeconds: number;
}

/**
 * One counted hit against `key`. The window length is part of the stored key: a minute bucket and an hour
 * bucket share a `window_start` at every hour boundary and would otherwise merge into one row.
 *
 * Fails OPEN: if the limiter itself errors, the request goes through and the failure is logged. The rest of the
 * request needs the same database and would fail anyway, and a limiter must never be the reason a healthy
 * request is refused.
 */
export async function hit(key: string, window: RateLimitWindow): Promise<HitResult> {
  try {
    const { data, error } = await supabaseAdmin.rpc("rate_limit_hit", {
      p_key: `${key}:${window.windowSeconds}`,
      p_limit: window.limit,
      p_window_seconds: window.windowSeconds,
    });
    const row = Array.isArray(data) ? data[0] : data;
    if (error || !row) throw new Error(error?.message ?? "rate_limit_hit returned no row");
    return { allowed: row.allowed, retryAfterSeconds: row.retry_after_seconds };
  } catch (failure) {
    console.error("rate limiter failed open:", failure instanceof Error ? failure.message : failure);
    return { allowed: true, retryAfterSeconds: 0 };
  }
}

async function firstDenied(key: string, windows: readonly RateLimitWindow[]): Promise<HitResult | null> {
  for (const window of windows) {
    const result = await hit(key, window);
    // Short-circuit: a request already refused by the minute window must not also burn the hour budget.
    if (!result.allowed) return result;
  }
  return null;
}

/** Per-IP layer. No client address (a direct call, not through the platform edge) → not limited. */
export async function enforceIpLimit(request: Request): Promise<NextResponse | null> {
  const ip = clientIp(request);
  if (!ip) return null;
  const denied = await firstDenied(`ip:${ip}`, [IP_RATE_LIMIT]);
  return denied ? rateLimitedResponse(denied.retryAfterSeconds) : null;
}

/** Per-user layer for one route's rule. `subject` is the caller's `auth.users.id`. */
export async function enforceUserLimit(subject: string, rule: RateLimitRule): Promise<NextResponse | null> {
  const denied = await firstDenied(`user:${subject}:${rule}`, RATE_LIMIT_RULES[rule]);
  return denied ? rateLimitedResponse(denied.retryAfterSeconds) : null;
}

/** SEC-10: bounds on what one `POST /api/runs` may cost, checked before any anti-cheat work. */
export const MAX_BODY_BYTES = 4_000_000; // just under the platform's own 4.5 MB request cap
export const MAX_ROUTE_POINTS = 20_000; // a marathon at 1 point/s is ≈14,400
