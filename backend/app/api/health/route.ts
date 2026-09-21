import { NextResponse } from "next/server";
import { enforceIpLimit } from "@/lib/rate-limit";

/**
 * T2.1: bare health check — confirms the Vercel deployment is reachable.
 * No auth dependency on purpose. T2.20a: covered by the per-IP limit only (there is no user to key on); the limiter
 * fails open, so a database outage still lets this answer.
 */
export async function GET(request: Request) {
  const limited = await enforceIpLimit(request);
  if (limited) return limited;
  return NextResponse.json({ status: "ok" });
}
