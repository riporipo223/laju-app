import AuthenticationServices
import Combine
import Foundation
import Supabase

/// T2.3: tracks the current Supabase Auth session for the whole app.
///
/// `@MainActor` explicitly — `code-quality-audit.md` CQ-1 flagged that nothing in the existing tracking path
/// declares isolation, relying on an unenforced runtime convention instead. New code gets it declared from
/// the start rather than repeating that gap.
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: Session?
    /// True until the SDK's own Keychain-backed session restore (or lack thereof) has been checked once —
    /// lets a view distinguish "still loading" from "genuinely signed out" on first launch.
    @Published private(set) var hasCheckedInitialSession = false

    private let client: SupabaseClient
    private var authStateTask: Task<Void, Never>?

    init(client: SupabaseClient = SupabaseConfig.client) {
        self.client = client
        #if DEBUG
            // Debug builds only: lets an end-to-end check run on a build that cannot carry Sign in with Apple (a
            // free Personal Team, or the Simulator without a paid capability). The tokens are a REAL Supabase session
            // for a throwaway test user, passed in the launch environment — nothing here bypasses server-side auth.
            let environment = ProcessInfo.processInfo.environment
            if let access = environment["LAJU_DEBUG_ACCESS_TOKEN"],
               let refresh = environment["LAJU_DEBUG_REFRESH_TOKEN"] {
                Task { try? await client.auth.setSession(accessToken: access, refreshToken: refresh) }
            }
        #endif
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (_, session) in client.auth.authStateChanges {
                self.session = session
                hasCheckedInitialSession = true
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    var isSignedIn: Bool {
        session != nil
    }

    /// Completes a native Sign in with Apple flow — exchanges the identity token from
    /// `ASAuthorizationAppleIDCredential` for a Supabase session. Throws on any failure; the caller (the
    /// onboarding sign-in step) decides how to surface that to the user.
    func signInWithApple(idToken: String) async throws {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken)
        )
    }

    /// Where Supabase sends the browser back after Google's consent screen. Must appear, exactly, in the project's
    /// Auth → URL Configuration → Redirect URLs allow-list. Only its scheme is registered with
    /// `ASWebAuthenticationSession`; no Info.plist URL type is needed for that.
    nonisolated static let oauthRedirectURL = URL(string: "com.designbyripo.laju://auth-callback")!

    /// Google Sign-In through Supabase's generic OAuth flow (PKCE, `ASWebAuthenticationSession`) — deliberately not
    /// Google's own iOS SDK: one code path in the same `client.auth`, so the session lands in exactly the same place as
    /// the Apple one (`authStateChanges` → `session`) and nothing downstream can tell the providers apart.
    func signInWithGoogle() async throws {
        try await client.auth.signInWithOAuth(provider: .google, redirectTo: Self.oauthRedirectURL)
    }

    /// True when the user closed the system sheet themselves (Apple's `.canceled`, or the browser session's
    /// `.canceledLogin`) — not a failure worth an error message.
    nonisolated static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain, nsError.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        return nsError.domain == ASWebAuthenticationSessionError.errorDomain
            && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }

    /// A current access token, refreshed by the SDK if it has expired — authoritative even in the instant after a
    /// sign-in, before `session` (fed asynchronously by `authStateChanges`) has caught up. Throws when nobody is signed
    /// in.
    func freshAccessToken() async throws -> String {
        try await client.auth.session.accessToken
    }

    /// True only for "nobody is signed in" (the SDK's `sessionMissing`) — NOT for a failed refresh, a dropped
    /// connection or any other error while fetching a token, which say nothing about whether a session exists.
    nonisolated static func isNoSession(_ error: Error) -> Bool {
        guard let authError = error as? AuthError, case .sessionMissing = authError else { return false }
        return true
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
