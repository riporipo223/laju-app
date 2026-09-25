import SwiftUI

/// T4.1: shown when Create Club answers 403 `not_premium` — same visual language
/// `LeaderboardLockedView` established for a gated feature (lock icon, title, message, single CTA).
///
/// **Honest about T4.20's real state**: there is no purchase flow yet (T4.20c/StoreKit isn't built,
/// T4.20b's Apple verification is blocked on Apple Developer Program enrollment) — this screen says so
/// rather than showing a "Subscribe" button that would silently do nothing.
struct PremiumUpsellView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(LajuColor.accent)

            Text("Butuh Laju Premium")
                .font(LajuFont.heading)
                .foregroundStyle(LajuColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("Bikin club cuma bisa dari akun Premium. Langganan Premium belum tersedia di app — coba lagi nanti.")
                .font(LajuFont.body)
                .foregroundStyle(LajuColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    PremiumUpsellView()
        .padding()
        .preferredColorScheme(.dark)
}
