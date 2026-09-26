import SwiftUI

/// product-spec.md §4.24 AC12: owner/admin only, gated on the Circle being a Premium Club — a 403
/// `not_premium_club` swaps this screen for `PremiumCircleUpsellView`, same pattern
/// `CreateChallengeView` uses. Top-5 contributors ranked by distance (confirmed 2026-09-26).
struct ClubAnalyticsView: View {
    let clubId: String

    @StateObject private var model = ClubAnalyticsViewModel()

    var body: some View {
        Group {
            if model.isPremiumRequired {
                ScrollView { PremiumCircleUpsellView().padding() }
            } else if let analytics = model.analytics {
                content(for: analytics)
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(LajuColor.error)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Circle Analytics")
        .task { await model.load(clubId: clubId) }
        .refreshable { await model.load(clubId: clubId) }
    }

    private func content(for analytics: ClubAnalyticsResponse) -> some View {
        List {
            Section("30 Hari Terakhir") {
                statRow(label: "Total Jarak", value: DistanceFormatter.format(meters: analytics.totalDistanceMeters))
                statRow(label: "Total Poin", value: "\(analytics.totalPoints)")
                statRow(label: "Member Aktif", value: "\(analytics.activeMemberCount)")
            }

            Section("Top 5 Kontributor") {
                if analytics.topContributors.isEmpty {
                    Text("Belum ada kontribusi dalam 30 hari terakhir.")
                        .foregroundStyle(LajuColor.textSecondary)
                } else {
                    ForEach(Array(analytics.topContributors.enumerated()), id: \.element.id) { index, contributor in
                        HStack {
                            Text("\(index + 1).")
                                .foregroundStyle(LajuColor.textSecondary)
                            Text(contributor.userId)
                                .foregroundStyle(LajuColor.textPrimary)
                            Spacer()
                            Text(DistanceFormatter.format(meters: contributor.distanceMeters))
                                .foregroundStyle(LajuColor.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(LajuColor.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(LajuColor.textPrimary)
        }
    }
}

#Preview {
    NavigationStack {
        ClubAnalyticsView(clubId: "club-1")
    }
    .preferredColorScheme(.dark)
}
