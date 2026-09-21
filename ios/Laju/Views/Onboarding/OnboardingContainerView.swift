import SwiftUI

/// Onboarding flow (product-spec/user-flow.md §2.1), structured on reference #4 (Peloton): full-bleed emotional
/// moment → headline → SSO pill → permission context → system prompt. Step order here (SSO before location
/// permission) is a deliberate 2026-09-14 sequencing decision, differing from user-flow.md's original text
/// (permission before signup) — chosen to match the Peloton reference structure; user-flow.md should be
/// updated to match if this order is kept.
///
/// `profile` (2026-09-21) sits between sign-in and the location prompt and is skipped when the signed-in account
/// already has a profile (a returning user on a new device) or nobody is signed in (the debug skip).
enum OnboardingStep: Int {
    case welcome, coreLoop, signIn, profile, permission
}

struct OnboardingContainerView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var step: OnboardingStep = .welcome
    @State private var isRouting = false
    @StateObject private var locationService = LocationTrackingService()
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            LajuColor.background.ignoresSafeArea()

            Group {
                switch step {
                case .welcome:
                    OnboardingWelcomeStep(onContinue: advance)
                case .coreLoop:
                    OnboardingCoreLoopStep(onContinue: advance)
                case .signIn:
                    OnboardingSignInStep(onContinue: { Task { await routeAfterSignIn() } })
                case .profile:
                    OnboardingProfileStep(
                        accessToken: { try await authService.freshAccessToken() },
                        onContinue: advance
                    )
                case .permission:
                    OnboardingPermissionStep(locationService: locationService, onFinished: onComplete)
                }
            }
            .id(step)
            .overlay {
                if isRouting {
                    ProgressView().tint(LajuColor.accent)
                }
            }
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            )
        }
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        go(to: next)
    }

    private func go(to next: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.35)) { step = next }
    }

    /// After sign-in: ask the server whether this account already has a profile. Nobody signed in (the debug skip) or
    /// an
    /// existing profile → straight to the location step. A missing profile, or ANY trouble reaching the server
    /// (a dropped connection, a failed token refresh) → the profile step: showing it beats silently skipping it, and
    /// only a genuinely absent session is allowed to mean "skip". (A first version treated every token error as "no
    /// session" and skipped the profile step on a flaky connection.)
    private func routeAfterSignIn() async {
        isRouting = true
        defer { isRouting = false }
        let jwt: String
        do {
            jwt = try await authService.freshAccessToken()
        } catch {
            go(to: AuthService.isNoSession(error) ? .permission : .profile)
            return
        }
        let hasProfile = await (try? APIClient().hasProfile(jwt: jwt)) ?? false
        go(to: hasProfile ? .permission : .profile)
    }
}
