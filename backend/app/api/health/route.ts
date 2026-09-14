import { NextResponse } from "next/server";

/**
 * T2.1: bare health check — confirms the Vercel deployment is reachable.
 * No DB/auth dependency here on purpose; that's exercised by later routes.
 */
export function GET() {
  return NextResponse.json({ status: "ok" });
}
