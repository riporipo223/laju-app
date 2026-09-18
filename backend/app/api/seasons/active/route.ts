import { NextResponse } from "next/server";
import { isAuthFailure, requireAuthenticatedIdentity } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

interface SeasonRow {
  id: string;
  name: string;
  start_at: string;
  end_at: string;
  status: string;
}

/**
 * T2.17: database-api-spec.md §2.5. Response is identical for every caller (no user-specific data), but
 * still requires a valid Supabase JWT per the spec's general "Requests without a valid Supabase JWT →
 * 401" rule — uses `requireAuthenticatedIdentity` (not the heavier `requireUser`) since no `user` row
 * lookup is needed to build this response.
 *
 * Season lifecycle transitions (upcoming → active → ended) are explicitly out of scope (Fase 3, T3.6) —
 * this only reads whichever row already has `status='active'` (seeded by this task's own migration).
 */
export async function GET(request: Request) {
  const identity = await requireAuthenticatedIdentity(request);
  if (isAuthFailure(identity)) return identity.response;

  const { data: season, error } = await supabaseAdmin
    .from("season")
    .select("id, name, start_at, end_at, status")
    .eq("status", "active")
    .maybeSingle<SeasonRow>();

  if (error) {
    return NextResponse.json({ error: "Could not load active season" }, { status: 500 });
  }
  if (!season) {
    return NextResponse.json({ error: "No active season" }, { status: 404 });
  }

  const daysRemaining = Math.max(0, Math.ceil((new Date(season.end_at).getTime() - Date.now()) / MS_PER_DAY));

  return NextResponse.json({
    id: season.id,
    name: season.name,
    start_at: season.start_at,
    end_at: season.end_at,
    status: season.status,
    days_remaining: daysRemaining,
  });
}
