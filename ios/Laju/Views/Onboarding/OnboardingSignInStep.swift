import SwiftUI

/// **Visual stub, not real auth.** Fase 1 has no backend/account system at all (this whole app is local-only
/// Core Data) and no Sign In with Apple entitlement is configured in the project — wiring up the real
/// `AuthenticationServices` flow here would either fail at runtime or silently need Fase 2's backend to mean
/// anything. This button matches reference #4's pill styling and position (primary SSO action) but simply
/// advances to the next step — real auth is Fase 2 work, not something to fake now.
struct OnboardingSignInStep: View {
    let onContinue: () -> Void

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
            Spacer()
            Spacer()

            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                    Text("Sign in with Apple")
                }
            }
            .buttonStyle(.lajuPrimary)
        }
        .padding(24)
    }
}

#Preview {
    ZStack {
        LajuColor.background.ignoresSafeArea()
        OnboardingSignInStep(onContinue: {})
    }
}
