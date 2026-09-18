import Foundation
import Supabase

/// T2.3: the shared Supabase client, configured once for the whole app.
///
/// The anon key below is meant to be public — Supabase's own security model protects data via Row Level
/// Security, not by keeping this key secret (same reasoning as the web `NEXT_PUBLIC_SUPABASE_ANON_KEY`
/// convention `backend/.env.local` already follows). It is safe to embed in the client binary. The
/// `service_role` key must never appear here — that one stays backend-only (database-api-spec.md §2.1b).
///
/// Session persistence (product-spec AC 4.1.3) is handled by the SDK itself: `AuthClient`'s default
/// `sessionStorage` is Keychain-backed, so a signed-in session survives an app restart with no extra
/// configuration on our side — verified on-device as part of T2.3's DoD, not just assumed from the docs.
enum SupabaseConfig {
    static let projectURL = URL(string: "https://qfjavbrwhfjkjremtvol.supabase.co")!
    // A JWT is one unbreakable token — splitting it would need string concatenation across lines, which is
    // worse than a scoped lint exception for exactly this one line.
    // swiftlint:disable:next line_length
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFmamF2YnJ3aGZqa2pyZW10dm9sIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk2NTMyMTcsImV4cCI6MjEwNTIyOTIxN30.5sGFGV5Oluq6x2g99QTEbCTdR1RKVzoapvC5mYeSjJc"

    static let client = SupabaseClient(supabaseURL: projectURL, supabaseKey: anonKey)
}
