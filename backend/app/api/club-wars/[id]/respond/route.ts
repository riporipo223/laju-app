import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { errorResponse, productionDeps } from "@/lib/club-war/http";
import { respondToChallenge } from "@/lib/club-war/lifecycle";

/**
 * T4.2b: an invited club's owner/admin accepts or declines. Body: `{ accept: boolean }`.
 * Returns the war's status afterwards: `pending` (other invites outstanding), `active`, or `dissolved`
 * (declined, past the 24h deadline, or the inviter's Premium lapsed — no record for anyone, §4.19 AC7/AC12).
 */
export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(request, "clubwar.respond");
  if (isAuthFailure(auth)) return auth.response;

  let body: { accept?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse("invalid_request");
  }

  const { id } = await context.params;
  const result = await respondToChallenge(productionDeps(), {
    callerUserId: auth.user.id,
    warId: id,
    accept: body.accept,
  });
  if (!result.ok) return errorResponse(result.error);
  return NextResponse.json({ war_id: id, status: result.value.status });
}
