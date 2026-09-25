import SwiftUI

/// T4.1b: a club's member list, reached from `ClubBrowseView` (tap a row) — shows a "Leave Club" button
/// on the caller's own row, since self-leave is the only leave flow in v1 (owner-remove-member is admin
/// tooling, deferred behind T4.20b).
struct ClubMemberListView: View {
    let clubId: String
    let clubName: String

    @StateObject private var model = ClubMemberListViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
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
