import Foundation

/// `POST /api/profile/complete` (database-api-spec.md §2.1, T2.4). `display_name` is left out on purpose: the server
/// defaults it to the username, and there is no separate field for it in the onboarding step.
/// Region fields removed 2026-09-22 (decision D1 reversed — product-spec.md §4.1): region is no longer collected
/// at all. The server ignores any `region_*` keys an older build still sends, so a stale client keeps working.
struct CompleteProfileRequest: Encodable, Equatable, Sendable {
    let username: String
}

/// The body of the server's "signed in, but no profile row yet" 401 — its `code` is what tells the app to show the
/// profile step instead of treating the 401 as a broken session.
struct AuthErrorBody: Decodable {
    let code: String?
}
