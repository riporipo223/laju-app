import { createClient } from "@supabase/supabase-js";

/**
 * Server-only Supabase client, using the service_role key.
 *
 * Never imported by anything that ships to the browser (database-api-spec.md §2.1b: the service-role key
 * must never reach the mobile client, and by the same reasoning never reach a client bundle here either —
 * this file lives under `lib/`, imported only by API route handlers, never by a `"use client"` component).
 */
export const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
  { auth: { autoRefreshToken: false, persistSession: false } }
);
