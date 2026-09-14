import SwiftUI

/// Onboarding flow (product-spec/user-flow.md §2.1), structured on reference #4 (Peloton): full-bleed emotional
/// moment → headline → SSO pill → permission context → system prompt. Step order here (SSO before location
/// permission) is a deliberate 2026-09-14 sequencing decision, differing from user-flow.md's original text
/// (permission before signup) — chosen to match the Peloton reference structure; user-flow.md should be
/// updated to match if this order is kept.
enum OnboardingStep: Int {
    case welcome, coreLoop, signIn, permission
}

struct OnboardingContainerView: View {
    @State private var step: OnboardingStep = .welcome
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
                    OnboardingSignInStep(onContinue: advance)
                case .permission:
                    OnboardingPermissionStep(locationService: locationService, onFinished: onComplete)
                }
            }
            .id(step)
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
        withAnimation(.easeInOut(duration: 0.35)) { step = next }
    }
}
