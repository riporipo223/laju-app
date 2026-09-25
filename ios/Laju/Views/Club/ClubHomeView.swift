import SwiftUI

/// Club tab root (2026-09-24 nav restructure, Bagian A item 4 + B item 6). Moved from `ProfileView`'s old
/// DEBUG-only `clubSection` scaffold — this is now a real tab, not a hidden debug link, so the `#if DEBUG`
/// gate is dropped: `ClubWarView`'s own error mapping already handles the ungated case gracefully
/// (`not_premium_club` → "Club War butuh Club Premium — belum tersedia."), and the backend
/// (`backend/app/api/club-wars/route.ts`, T4.2b) is real, deployed code, not a stub — it deliberately denies
/// every caller with 403 `not_premium_club` until T4.20 (Premium) ships, by its own doc comment.
///
/// Club itself (T4.1 — create/join/leave/browse, member list): **Create Club only** is built
/// (2026-09-25, Premium-gated — `POST /api/clubs`, `lib/club/premium.ts`). Join/leave/browse/member list
/// remain unbuilt, separate scope, still tracked as T4.1.
struct ClubHomeView: View {
    @State private var showingCreateClub = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                clubWarEntry
                createClubButton
                clubComingSoon
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

    private var clubComingSoon: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.title2)
                .foregroundStyle(LajuColor.textSecondary)
            Text("Club (buat, gabung, anggota) belum dibangun")
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
    NavigationStack {
        ClubHomeView()
    }
    .preferredColorScheme(.dark)
}
