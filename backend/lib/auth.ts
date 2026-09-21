import { NextResponse } from "next/server";
import { enforceIpLimit, enforceUserLimit, type RateLimitRule } from "./rate-limit";
import { supabaseAdmin } from "./supabase";

/** Shape of a row from the `user` table (database-api-spec.md §1 ERD) — only the columns this module reads. */
export interface UserRow {
  id: string;
  auth_user_id: string;
  deleted_at: string | null;
  region_kecamatan: string | null;
  region_kabupaten_kota: string | null;
  region_provinsi: string | null;
}

export type AuthSuccess = { user: UserRow };
export type AuthFailure = { response: NextResponse };
export type AuthResult = AuthSuccess | AuthFailure;

export type IdentitySuccess = { authUserId: string };
export type IdentityResult = IdentitySuccess | AuthFailure;

export function isAuthFailure(result: AuthResult | IdentityResult): result is AuthFailure {
  return "response" in result;
}

function unauthorized(message: string): AuthFailure {
  return { response: NextResponse.json({ error: message }, { status: 401 }) };
}

/**
 * Verifies the request's `Authorization: Bearer <jwt>` header against Supabase's Auth server and returns
 * the caller's `auth.users.id` — nothing more. No `user` table lookup, so this works even before a `user`
 * row exists.
 *
 * That is exactly `POST /api/profile/complete`'s (T2.4) situation: it is the endpoint that CREATES the
 * first `user` row for a newly-signed-up identity, so `requireUser` below — which requires that row to
 * already exist — cannot gate it without a chicken-and-egg problem. Every other route wants the full
 * `requireUser` check; only profile-completion wants this narrower one.
 *
 * Verification goes through Supabase's own Auth server (`auth.getUser`), not local JWT-signature
 * verification — this project's keys are the legacy HS256 model (confirmed via `supabase projects
 * api-keys`), and `getUser` additionally catches revocation/rotation cases a pure signature check would
 * miss, at the cost of one network round-trip per request. Acceptable for v1; revisit if p95 latency
 * (tech-spec.md §4 NFR) is ever threatened by it.
 */
export async function requireAuthenticatedIdentity(request: Request, rule?: RateLimitRule): Promise<IdentityResult> {
  // T2.20a (SEC-9): the per-IP limit runs BEFORE the Auth call below — an unauthenticated flood otherwise costs
  // one Supabase Auth request per hit — and the per-user limit right after the caller is known.
  const ipLimited = await enforceIpLimit(request);
  if (ipLimited) return { response: ipLimited };

  const authHeader = request.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return unauthorized("Missing or malformed Authorization header");
  }
  const jwt = authHeader.slice("Bearer ".length).trim();
  if (!jwt) {
    return unauthorized("Missing or malformed Authorization header");
  }

  const { data: authData, error: authError } = await supabaseAdmin.auth.getUser(jwt);
  if (authError || !authData.user) {
    return unauthorized("Invalid or expired token");
  }

  if (rule) {
    const userLimited = await enforceUserLimit(authData.user.id, rule);
    if (userLimited) return { response: userLimited };
  }

  return { authUserId: authData.user.id };
}

/**
 * Verifies the request's `Authorization: Bearer <jwt>` header and resolves it to a `user` row.
 *
 * database-api-spec.md §3: "Any authenticated request where the caller's own `User.deleted_at` is
 * non-null" must be rejected — checked by looking up `deleted_at` on every request, not by trusting the
 * token alone, since a JWT stays cryptographically valid until it expires even after `DELETE /api/account`
 * (§2.1b) deletes the Auth identity. That lookup happens here, once, so every route that calls this gets
 * it for free rather than re-implementing it.
 *
 * Built on `requireAuthenticatedIdentity` — this is that same check, plus the `user` row lookup and
 * `deleted_at` gate. Every route except `POST /api/profile/complete` (T2.4) should call this one.
 */
export async function requireUser(request: Request, rule?: RateLimitRule): Promise<AuthResult> {
  const identity = await requireAuthenticatedIdentity(request, rule);
  if (isAuthFailure(identity)) return identity;

  const { data: userRow, error: userError } = await supabaseAdmin
    .from("user")
    .select("id, auth_user_id, deleted_at, region_kecamatan, region_kabupaten_kota, region_provinsi")
    .eq("auth_user_id", identity.authUserId)
    .maybeSingle<UserRow>();

  if (userError) {
    return unauthorized("Could not resolve user record");
  }
  if (!userRow) {
    // Authenticated with Supabase, but has no `user` row yet (T2.4's profile-completion endpoint
    // creates it). Not this middleware's job to create one — that would silently do T2.4's work here.
    return unauthorized("No user profile exists for this identity");
  }
  if (userRow.deleted_at !== null) {
    return unauthorized("This account has been deleted");
  }

  return { user: userRow };
}
