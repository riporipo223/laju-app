/**
 * Test-only: obtain a genuine Supabase Auth access token for a user WITHOUT the email/password provider.
 *
 * The project is Apple-only (pre-launch-checklist.md §5), so the email provider is switched off and
 * `signInWithPassword` no longer works. Tests need real JWTs — `requireAuthenticatedIdentity` verifies them
 * against Supabase's Auth server via `auth.getUser`, and a hand-minted token would test our forgery instead of
 * that path. So: the user is created with the `service_role` Admin API, and a session is issued from a
 * server-generated magic-link token hash (`generateLink` → `verifyOtp`). The result is an ordinary access token
 * issued by Supabase itself; no password ever exists, and no public sign-in path is involved.
 */
import type { SupabaseClient } from "@supabase/supabase-js";

export async function createTestAuthUser(
  admin: SupabaseClient,
  anon: SupabaseClient,
  email: string
): Promise<{ authUserId: string; accessToken: string }> {
  const { data: created, error: createError } = await admin.auth.admin.createUser({ email, email_confirm: true });
  if (createError || !created.user) throw new Error(`Could not create test auth user: ${createError?.message}`);

  const { data: link, error: linkError } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  const tokenHash = link?.properties?.hashed_token;
  if (linkError || !tokenHash) throw new Error(`Could not generate a session link: ${linkError?.message}`);

  const { data: verified, error: verifyError } = await anon.auth.verifyOtp({ token_hash: tokenHash, type: "magiclink" });
  if (verifyError || !verified.session) throw new Error(`Could not issue a test session: ${verifyError?.message}`);

  return { authUserId: created.user.id, accessToken: verified.session.access_token };
}
