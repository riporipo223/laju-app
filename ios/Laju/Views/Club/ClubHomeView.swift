import SwiftUI

/// Club tab root (2026-09-24 nav restructure, Bagian A item 4 + B item 6). Moved from `ProfileView`'s old
/// DEBUG-only `clubSection` scaffold — this is now a real tab, not a hidden debug link, so the `#if DEBUG`
/// gate is dropped: `ClubWarView`'s own error mapping already handles the ungated case gracefully
/// (`not_premium_club` → "Club War butuh Club Premium — belum tersedia."), and the backend
/// (`backend/app/api/club-wars/route.ts`, T4.2b) is real, deployed code, not a stub — it deliberately denies
/// every caller with 403 `not_premium_club` until T4.20 (Premium) ships, by its own doc comment.
///
/// Club itself (T4.1 — create/join/leave/browse, member list): **Create Club + browse/join/leave/member
/// list all built** (T4.1a/b, 2026-09-25). Create Club is Premium-gated (`lib/club/premium.ts`);
/// browse/join/leave/member list need no Premium check. Admin tools (analytics, internal challenges)
/// remain deferred, blocked on T4.20b.
struct ClubHomeView: View {
    @State private var showingCreateClub = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                clubWarEntry
                createClubButton
                browseClubsButton
            }
            .padding()
        }
        .background(LajuColor.background.ignoresSafeArea())
        .navigationTitle("Club")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingCreateClub) {
            CreateClubView(onCreated: {})
        }
    }

    private var createClubButton: some View {
        Button("Create Club") { showingCreateClub = true }
            .buttonStyle(.lajuPrimary)
            .frame(maxWidth: .infinity)
    }

    private var browseClubsButton: some View {
        NavigationLink {
            ClubBrowseView()
        } label: {
            HStack {
                Text("Browse Clubs")
                    .font(LajuFont.body)
                    .foregroundStyle(LajuColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(LajuColor.textSecondary)
            }
            .padding()
            .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var clubWarEntry: some View {
        NavigationLink {
            ClubWarView()
        } label: {
            HStack {
                Text("Club Saya")
                    .font(LajuFont.heading)
                    .foregroundStyle(LajuColor.textPrimary)
                Spacer()
                Text("Club War")
                    .font(LajuFont.label)
                    .foregroundStyle(LajuColor.textSecondary)
                Image(systemName: "chevron.right")
                    .foregroundStyle(LajuColor.textSecondary)
            }
            .padding()
            .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
        }
    }

}

#Preview {
    NavigationStack {
        ClubHomeView()
    }
    .preferredColorScheme(.dark)
}
