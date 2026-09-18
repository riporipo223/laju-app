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
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (_, session) in client.auth.authStateChanges {
                self.session = session
                self.hasCheckedInitialSession = true
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

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
