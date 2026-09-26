import SwiftUI

/// Circle tab root (2026-09-24 nav restructure, Bagian A item 4 + B item 6; display copy renamed
/// Club→Circle 2026-09-26, product-spec.md §4.24's header note — internal type/file names unchanged).
/// Moved from `ProfileView`'s old DEBUG-only `clubSection` scaffold — this is now a real tab, not a
/// hidden debug link, so the `#if DEBUG` gate is dropped: `ClubWarView`'s own error mapping already
/// handles the ungated case gracefully (`not_premium_club` → "Club War butuh Club Premium — belum
/// tersedia."), and the backend (`backend/app/api/club-wars/route.ts`, T4.2b) is real, deployed code,
/// not a stub — it deliberately denies every caller with 403 `not_premium_club` until T4.20 (Premium)
/// ships, by its own doc comment. "Club War" itself stays unrenamed here too (also decided to become
/// "Circle War" per product-spec.md §4.19, but deliberately deferred until its build hold is lifted).
///
/// Circle itself (T4.1 — create/join/leave/browse, member list): **create + browse/join/leave/member
/// list all built**, free for every tier (Premium gate on create reverted 2026-09-26). Admin tools
/// (analytics, internal challenges) remain deferred, blocked on T4.20b.
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
        .navigationTitle("Circle")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingCreateClub) {
            CreateClubView(onCreated: {})
        }
    }

    private var createClubButton: some View {
        Button("Create Circle") { showingCreateClub = true }
            .buttonStyle(.lajuPrimary)
            .frame(maxWidth: .infinity)
    }

    private var browseClubsButton: some View {
        NavigationLink {
            ClubBrowseView()
        } label: {
            HStack {
                Text("Browse Circles")
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
                Text("Circle Saya")
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
