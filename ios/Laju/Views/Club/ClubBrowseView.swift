import SwiftUI

/// T4.1b: browse clubs to join — reached from `ClubHomeView`'s "Browse Clubs" button. Tapping a row
/// pushes `ClubMemberListView`; the Join button is separate (doesn't need a member list first).
struct ClubBrowseView: View {
    @StateObject private var model = ClubBrowseViewModel()
    @State private var inviteCodeDraft = ""

    var body: some View {
        List {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(LajuColor.error)
            }
            ForEach(model.clubs) { club in
                clubRow(club)
                    .onAppear {
                        if club.id == model.clubs.last?.id {
                            Task { await model.loadMore() }
                        }
                    }
            }
            if model.isLoadingMore {
                ProgressView()
            }
        }
        .navigationTitle("Browse Clubs")
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func clubRow(_ club: ClubSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink {
                ClubMemberListView(clubId: club.clubId, clubName: club.name)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(club.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LajuColor.textPrimary)
                    if let description = club.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(LajuColor.textSecondary)
                    }
                    Text("\(club.memberCount) member · \(club.privacy == "public" ? "Public" : "Invite Only")")
                        .font(.caption2)
                        .foregroundStyle(LajuColor.textSecondary)
                }
            }

            if model.invitePromptClubId == club.clubId {
                HStack {
                    TextField("Invite code", text: $inviteCodeDraft)
                        .textInputAutocapitalization(.characters)
                    Button("Join") {
                        Task {
                            if await model.joinClub(club, inviteCode: inviteCodeDraft) {
                                inviteCodeDraft = ""
                            }
                        }
                    }
                }
            } else {
                Button("Join") {
                    Task { await model.joinClub(club, inviteCode: nil) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(LajuColor.accent)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ClubBrowseView()
    }
    .preferredColorScheme(.dark)
}
