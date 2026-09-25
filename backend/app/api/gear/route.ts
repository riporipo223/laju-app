import { NextResponse } from "next/server";
import { isAuthFailure, requireUser } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/supabase";

const MAX_MODEL_LENGTH = 100;
const MAX_SIZE_LENGTH = 20;

/**
 * T4.21 (v1 scoping session, phase-4-backlog.md, 2026-09-25): the v1 brand list — validated here, not by
 * a DB CHECK/enum on `gear.brand` (20260925120000_activity_detail_and_gear_schema.sql), so adding a 13th
 * brand later is a one-line change here, not a migration.
 */
const VALID_BRANDS = [
  "Nike",
  "Adidas",
  "Hoka",
  "Asics",
  "Brooks",
  "New Balance",
  "Saucony",
  "Puma",
  "Mizuno",
  "On",
  "Under Armour",
  "Other",
] as const;

interface CreateGearBody {
  brand?: unknown;
  model?: unknown;
  size?: unknown;
}

/**
 * T4.21: add a shoe to the caller's own gear list. Used from both Save Activity's inline "Add Gear" and
 * the profile screen — same table, no run-scoped copy (phase-4-backlog.md T4.21 scope note).
 */
export async function POST(request: Request) {
  const auth = await requireUser(request, "gear.create");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  let body: CreateGearBody;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { brand, model, size } = body;
  if (typeof brand !== "string" || !VALID_BRANDS.includes(brand as (typeof VALID_BRANDS)[number])) {
    return NextResponse.json({ error: `brand must be one of: ${VALID_BRANDS.join(", ")}` }, { status: 400 });
  }
  if (model !== undefined && model !== null && typeof model !== "string") {
    return NextResponse.json({ error: "model must be a string" }, { status: 400 });
  }
  if (size !== undefined && size !== null && typeof size !== "string") {
    return NextResponse.json({ error: "size must be a string" }, { status: 400 });
  }
  const trimmedModel = typeof model === "string" ? model.trim() : null;
  const trimmedSize = typeof size === "string" ? size.trim() : null;
  if (trimmedModel !== null && trimmedModel.length > MAX_MODEL_LENGTH) {
    return NextResponse.json({ error: `model may be at most ${MAX_MODEL_LENGTH} characters` }, { status: 400 });
  }
  if (trimmedSize !== null && trimmedSize.length > MAX_SIZE_LENGTH) {
    return NextResponse.json({ error: `size may be at most ${MAX_SIZE_LENGTH} characters` }, { status: 400 });
  }

  const { data: gear, error } = await supabaseAdmin
    .from("gear")
    .insert({ user_id: user.id, brand, model: trimmedModel || null, size: trimmedSize || null })
    .select("id, brand, model, size, created_at")
    .single<{ id: string; brand: string; model: string | null; size: string | null; created_at: string }>();

  if (error || !gear) {
    return NextResponse.json({ error: "Could not create gear" }, { status: 500 });
  }

  return NextResponse.json(
    { gear_id: gear.id, brand: gear.brand, model: gear.model, size: gear.size, created_at: gear.created_at },
    { status: 201 }
  );
}

/** T4.21: the caller's own gear list, for Save Activity's prefill and the profile screen. */
export async function GET(request: Request) {
  const auth = await requireUser(request, "gear.list");
  if (isAuthFailure(auth)) return auth.response;
  const { user } = auth;

  const { data, error } = await supabaseAdmin
    .from("gear")
    .select("id, brand, model, size, created_at")
    .eq("user_id", user.id)
    .order("created_at", { ascending: true });

  if (error) {
    return NextResponse.json({ error: "Could not load gear" }, { status: 500 });
  }

  const rows = (data ?? []) as { id: string; brand: string; model: string | null; size: string | null; created_at: string }[];
  return NextResponse.json({
    gear: rows.map((row) => ({
      gear_id: row.id,
      brand: row.brand,
      model: row.model,
      size: row.size,
      created_at: row.created_at,
    })),
  });
}
