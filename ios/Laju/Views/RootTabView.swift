import SwiftUI

/// The app's navigation shell (T2.0a, 2026-09-17) — replaces `RunTrackingView` as the root.
///
/// Built now rather than with the first leaderboard screen because T2.20 (global leaderboard), T3.5 (local
/// leaderboard) and T3.9 (season info) each build a screen with no way to reach it until this exists; the
/// audit that found that gap noted all three were unreachable-by-construction. T3.9's `SeasonInfoView` has
/// no tab of its own — it is reached from a toolbar button on `LeaderboardView`.
///
/// **5-tab order, decided 2026-09-24: Social, Club, Track, Ranks, You.** Reverses the older "only tabs with
/// real content are shown" rule — Social (T4.15) and Club (T4.1) had no real content yet when the order was
/// decided, but the tab order was wanted now rather than only once each feature lands. **Social updated the
/// same day**: `SocialHomeView` is now a real feed screen wired to `backend/app/api/social/posts/*`, not a
/// placeholder — see its own header comment for why it still can't succeed against production today (the
/// migration is written but not applied). `ClubHomeView` remains a placeholder for Club itself (T4.1, not
/// started) with only its Club War sub-feature (T4.2c) built — see its own note.
struct RootTabView: View {
    @State private var selection: LajuTab = .track

    var body: some View {
        TabView(selection: $selection) {
            SocialHomeView()
                .tabItem { Label(LajuTab.social.title, systemImage: LajuTab.social.symbol) }
                .tag(LajuTab.social)

            NavigationStack {
                ClubHomeView()
            }
            .tabItem { Label(LajuTab.club.title, systemImage: LajuTab.club.symbol) }
            .tag(LajuTab.club)

            RunTrackingView()
                .tabItem { Label(LajuTab.track.title, systemImage: LajuTab.track.symbol) }
                .tag(LajuTab.track)

            NavigationStack {
                RanksView()
            }
            .tabItem { Label(LajuTab.leaderboard.title, systemImage: LajuTab.leaderboard.symbol) }
            .tag(LajuTab.leaderboard)

            // `ProfileView` has a `navigationTitle`, so it needs a stack of its own — `RunTrackingView`
            // brings its own (it hides the bar and uses it only for the History push).
            NavigationStack {
                ProfileView()
            }
            .tabItem { Label(LajuTab.you.title, systemImage: LajuTab.you.symbol) }
            .tag(LajuTab.you)
        }
        // `LajuApp` already forces `.preferredColorScheme(.dark)` on the whole window, which covers the tab
        // bar too — an explicit `.toolbarBackground(..., for: .tabBar)` here was tried and removed as
        // redundant (2026-09-17).
        .tint(LajuColor.accent)
    }
}

/// Tab identity, kept separate from the view so titles/symbols have one home and future tabs can be added
/// without touching `RootTabView`'s body shape.
enum LajuTab: Hashable {
    case social
    case club
    case track
    case leaderboard
    case you

    var title: String {
        switch self {
        case .social: "Social"
        case .club: "Circle"
        case .track: "Track"
        case .leaderboard: "Ranks"
        case .you: "You"
        }
    }

    var symbol: String {
        switch self {
        case .social: "person.2.wave.2.fill"
        case .club: "shield.lefthalf.filled"
        case .track: "figure.run"
        case .leaderboard: "trophy.fill"
        case .you: "person.fill"
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .preferredColorScheme(.dark)
}
