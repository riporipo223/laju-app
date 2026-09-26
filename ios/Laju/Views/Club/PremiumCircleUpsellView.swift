import SwiftUI

/// Shown when a Circle-scoped action answers 403 `not_premium_club` — creating a challenge (§4.24
/// AC13) or viewing analytics (§4.24 AC12). Same visual language `LeaderboardLockedView` established
/// for a gated feature (icon, title, message, no dead-end CTA) — checked before writing this: the
/// prior `PremiumUpsellView.swift` (Create Circle's own upsell) was deleted 2026-09-26 because its
/// copy went factually wrong once Circle creation itself became free; this is a fresh view, not a
/// resurrection, scoped to Premium-gated Circle FEATURES (challenge/analytics), not Circle creation.
///
/// **Honest about T4.20's real state**, same as the deleted view was: no purchase flow yet
/// (T4.20c/StoreKit isn't built, T4.20b's Apple verification is blocked on Apple Developer Program
/// enrollment) — this screen says so rather than showing a "Subscribe" button that would silently do
/// nothing.
struct PremiumCircleUpsellView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(LajuColor.accent)

            Text("Butuh Laju Premium")
                .font(LajuFont.heading)
                .foregroundStyle(LajuColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(
                "Fitur ini cuma bisa dipakai kalau pemilik Circle punya Premium. "
                    + "Langganan Premium belum tersedia di app — coba lagi nanti."
            )
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
    PremiumCircleUpsellView()
        .padding()
        .preferredColorScheme(.dark)
}
