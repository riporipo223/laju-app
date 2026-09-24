import SwiftUI

/// Social tab root (2026-09-24 nav restructure, Bagian B item 6). Checked for existing content first:
/// no `Social`/`Friends`/`Events`-named view anywhere in `ios/Laju/Views`, no matching backend route in
/// `backend/app/api` — zero code exists (Social Feed is T4.15, not scheduled/started). Tab is still added,
/// per this task's own instruction, so the navbar order is right now rather than only once T4.15 lands.
struct SocialHomeView: View {
    var body: some View {
        NavigationStack {
            ComingSoonView(
                systemImage: "person.2.wave.2.fill",
                title: "Social belum dibangun",
                message: "Social Feed (T4.15) belum mulai dikerjakan. Lari, poin, dan level tetap berjalan "
                    + "seperti biasa."
            )
            .navigationTitle("Social")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

#Preview {
    SocialHomeView()
        .preferredColorScheme(.dark)
}
