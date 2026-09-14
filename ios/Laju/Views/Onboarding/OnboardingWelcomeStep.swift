import SwiftUI

/// Headline is user-flow.md §2.1's locked copy ("Lari yang berasa main game") — not re-invented, only
/// typeset: split across lines with "main game" in `accent` lime for emphasis (color-split concatenation,
/// `.foregroundColor` not `.foregroundStyle` — the only one of the two that composes across `Text` `+`).
struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            (
                Text("Lari yang berasa\n").foregroundColor(LajuColor.textPrimary)
                    + Text("main game.").foregroundColor(LajuColor.accent)
            )
            .font(.system(size: 40, weight: .heavy, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)

            Text("Setiap kilometer dapat poin. Setiap poin bawa kamu naik level.")
                .font(LajuFont.body)
                .foregroundStyle(LajuColor.textSecondary)
            Spacer()
            Spacer()

            Button("Lanjutkan", action: onContinue)
                .buttonStyle(.lajuPrimary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    OnboardingWelcomeStep(onContinue: {})
}
