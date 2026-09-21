import { NextResponse } from "next/server";
import { deleteAccount } from "@/lib/account-deletion";
import { isAuthFailure, requireAuthenticatedIdentity } from "@/lib/auth";

/**
 * T2.22: database-api-spec.md §2.1b. Authenticates with the Auth identity alone (`requireAuthenticatedIdentity`),
 * not `requireUser`: a caller whose `user` row is already soft-deleted (a previous attempt that failed at the
 * final Auth-identity step) must still be able to retry and finish, and an identity with no `user` row yet
 * (signed up, never completed the profile) must still be able to delete its account.
 *
 * A repeat call after full success has no valid JWT any more (the identity is gone), so it is answered `401`
 * by the auth check like any other request from a deleted account (§3).
 */
export async function DELETE(request: Request) {
  const identity = await requireAuthenticatedIdentity(request, "account.delete");
  if (isAuthFailure(identity)) return identity.response;

  try {
    await deleteAccount(identity.authUserId);
  } catch {
    return NextResponse.json({ error: "Could not delete account" }, { status: 500 });
  }
  return NextResponse.json({ deleted: true });
}
