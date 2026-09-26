import SwiftUI

/// T4.1b: a club's member list, reached from `ClubBrowseView` (tap a row) — shows a "Leave" button on
/// the caller's own row, and a kick button on any other row when the caller is owner/admin
/// (product-spec.md §4.24 AC23, free for every tier — never Premium-gated).
struct ClubMemberListView: View {
    let clubId: String
    let clubName: String

    @StateObject private var model = ClubMemberListViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                NavigationLink("Challenge") {
                    ChallengeView(clubId: clubId)
                }
                if model.canViewAnalytics {
                    NavigationLink("Circle Analytics") {
                        ClubAnalyticsView(clubId: clubId)
                    }
                }
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(LajuColor.error)
            }
            ForEach(model.members) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LajuColor.textPrimary)
                        Text(member.role == "owner" ? "Owner" : "Member")
                            .font(.caption)
                            .foregroundStyle(LajuColor.textSecondary)
                    }
                    Spacer()
                    if model.isCurrentUser(member), member.role != "owner" {
                        Button("Leave") {
                            Task {
                                await model.leave(clubId: clubId)
                                if model.didLeave { dismiss() }
                            }
                        }
                        .foregroundStyle(LajuColor.error)
                        .disabled(model.isLeaving)
                    } else if model.canKick(member) {
                        Button("Kick") {
                            Task { await model.kick(clubId: clubId, member: member) }
                        }
                        .foregroundStyle(LajuColor.error)
                        .disabled(model.isKicking)
                    }
                }
            }
        }
        .navigationTitle(clubName)
        .task { await model.load(clubId: clubId) }
    }
}

#Preview {
    NavigationStack {
        ClubMemberListView(clubId: "club-1", clubName: "Lari Pagi")
    }
    .preferredColorScheme(.dark)
}
