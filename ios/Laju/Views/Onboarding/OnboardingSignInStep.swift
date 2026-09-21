import AuthenticationServices
import SwiftUI

/// Sign-in step. **Two providers: Sign in with Apple and Google** — decision of 2026-09-21, which REVERSES the
/// 2026-09-17 "Apple only" decision (T2.3). Why: Android is on the roadmap and Google is the default there, and Google
/// through Supabase needs no paid Apple entitlement, which unblocks testing the real auth flow. Apple stays: with a
/// third-party login present, App Store Guideline 4.8 requires an equivalent privacy-preserving option. Still no
/// email/password (SEC-15). See product-spec.md §4.1 AC1 and pre-launch-checklist.md §5.
///
/// Both providers end in the same place — a Supabase session observed by `AuthService` — so nothing after this screen
/// knows or cares which one was used.
struct OnboardingSignInStep: View {
    @EnvironmentObject private var authService: AuthService
    let onContinue: () -> Void

    @State private var errorMessage: String?
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Simpan progresmu")
                .font(LajuFont.heading)
                .foregroundStyle(LajuColor.textPrimary)
            Text("Masuk supaya level dan streak-mu tetap aman.")
                .font(LajuFont.body)
                .foregroundStyle(LajuColor.textSecondary)
                .multilineTextAlignment(.center)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(LajuColor.error)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(Capsule())
            .disabled(isSigningIn)

            // Own styling on purpose (the design system's secondary button), not Google's default white pill —
            // the neon-lime identity would clash with it.
            Button("Sign in with Google", action: signInWithGoogle)
                .buttonStyle(LajuSecondaryButtonStyle())
                .disabled(isSigningIn)
        }
        .padding(24)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        errorMessage = nil
        switch result {
        case let .success(authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Gagal membaca kredensial Apple. Coba lagi."
                return
            }
            perform { try await authService.signInWithApple(idToken: idToken) }
        case let .failure(error):
            report(error)
        }
    }

    private func signInWithGoogle() {
        errorMessage = nil
        perform { try await authService.signInWithGoogle() }
    }

    /// The shared tail of both providers: run the sign-in, then continue or surface the failure.
    private func perform(_ signIn: @escaping () async throws -> Void) {
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await signIn()
                onContinue()
            } catch {
                report(error)
            }
        }
    }

    /// A user-cancelled sheet is reported as an error too — don't show a scary message for a deliberate cancel, just
    /// stay on this step silently.
    private func report(_ error: Error) {
        guard !AuthService.isUserCancellation(error) else { return }
        errorMessage = "Gagal masuk: \(error.localizedDescription)"
    }
}

#Preview {
    ZStack {
        LajuColor.background.ignoresSafeArea()
        OnboardingSignInStep(onContinue: {})
            .environmentObject(AuthService())
    }
}
