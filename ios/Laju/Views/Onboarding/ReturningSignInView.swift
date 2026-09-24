import SwiftUI

/// Shown to a previously-onboarded user who is currently signed out (explicit Logout from `ProfileView`, or
/// an expired/revoked session) — decided 2026-09-24 (Bagian B item 7): a returning user skips the full
/// onboarding flow (welcome/core-loop/profile/permission all already done on this account) and goes straight
/// back to sign-in. `hasCompletedOnboarding` (`LajuApp.swift`) stays `true` across this; only
/// `AuthService.session` differs.
///
/// Reuses `OnboardingSignInStep` as-is so both entry points share one sign-in implementation. `onContinue` is
/// a no-op here: `LajuApp`'s root `Group` reactively switches to `RootTabView` the instant
/// `authService.session` becomes non-nil (via `authStateChanges`), so no manual navigation is needed.
struct ReturningSignInView: View {
    var body: some View {
        ZStack {
            LajuColor.background.ignoresSafeArea()
            OnboardingSignInStep(onContinue: {})
        }
    }
}

#Preview {
    ReturningSignInView()
        .environmentObject(AuthService())
        .preferredColorScheme(.dark)
}
