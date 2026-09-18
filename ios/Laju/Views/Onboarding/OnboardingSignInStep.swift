import AuthenticationServices
import SwiftUI

/// T2.3: real Sign in with Apple, replacing the 2026-09-13 visual stub now that the backend (T2.1/T2.2) and
/// the entitlement/SPM wiring exist. Auth method decision (2026-09-17, T2.3): **Sign in with Apple only** —
/// no email/password, no other OAuth provider. Chosen to match this screen's existing design (reference #4,
/// Peloton-style single SSO pill, no form) and because it trivially satisfies App Store Guideline 4.8 (no
/// other OAuth provider is offered that Apple would need to sit alongside). This resolves product-spec.md
/// §4.1 AC1's "email/password atau OAuth" ambiguity — recorded there, not left implicit in code alone.
struct OnboardingSignInStep: View {
    @EnvironmentObject private var authService: AuthService
    let onContinue: () -> Void

    @State private var errorMessage: String?

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
                handle(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(Capsule())
        }
        .padding(24)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
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
            Task {
                do {
                    try await authService.signInWithApple(idToken: idToken)
                    onContinue()
                } catch {
                    errorMessage = "Gagal masuk: \(error.localizedDescription)"
                }
            }
        case let .failure(error):
            // User-cancelled is reported as an error too (ASAuthorizationError.canceled) — don't show a
            // scary message for a deliberate cancel, just stay on this step silently.
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = "Gagal masuk: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ZStack {
        LajuColor.background.ignoresSafeArea()
        OnboardingSignInStep(onContinue: {})
            .environmentObject(AuthService())
    }
}
