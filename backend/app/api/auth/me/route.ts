import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";

/**
 * T2.3: the minimal route that proves `requireUser` works end-to-end over real HTTP, not just as an
 * isolated function. Every future protected route (T2.4 onward) uses the exact same `requireUser` call —
 * this one exists so that claim is provable now, before any of those routes are built.
 */
export async function GET(request: Request) {
  const result = await requireUser(request, "auth.me");
  if (isAuthFailure(result)) return result.response;

  return NextResponse.json({ id: result.user.id, auth_user_id: result.user.auth_user_id });
}
