import SwiftUI

/// Generic "not built yet" placeholder, style borrowed from `LeaderboardLockedView` (icon, title, message,
/// centered, no CTA). Used for a tab/segment that must exist in the navbar now (2026-09-24 nav restructure)
/// even though its real content (Social, Club home, Club/Club War leaderboards) isn't built — an empty tab
/// beats no tab per this decision, unlike `RootTabView`'s older "only tabs with real content" rule.
struct ComingSoonView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(LajuColor.textSecondary)

            Text(title)
                .font(LajuFont.heading)
                .foregroundStyle(LajuColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(LajuFont.body)
                .foregroundStyle(LajuColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LajuColor.background.ignoresSafeArea())
    }
}
