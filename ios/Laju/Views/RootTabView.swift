import SwiftUI

/// The app's navigation shell (T2.0a, 2026-09-17) — replaces `RunTrackingView` as the root.
///
/// Built now rather than with the first leaderboard screen because T2.20 (global leaderboard), T3.5 (local
/// leaderboard) and T3.9 (season info) each build a screen with no way to reach it until this exists; the
/// audit that found that gap noted all three were unreachable-by-construction.
///
/// **Only tabs with real content are shown.** `LajuTab` carries the future cases so adding one is a two-line
/// change (an `enum` case plus its `tabItem` block) rather than a restructure, but a case with no screen
/// behind it is deliberately not rendered — an empty tab is worse than an absent one.
struct RootTabView: View {
    @State private var selection: LajuTab = .track

    var body: some View {
        TabView(selection: $selection) {
            RunTrackingView()
                .tabItem { Label(LajuTab.track.title, systemImage: LajuTab.track.symbol) }
                .tag(LajuTab.track)

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
///
/// `social` and `circle` are intentionally absent rather than present-but-disabled: `social` lands with
/// T2.20's leaderboard (tasks/phase-2), `circle` only if the Fase-4 Circle feature (T4.1) is promoted into
/// scope, which is not decided. Add the case here and one `tabItem` block above when either ships.
enum LajuTab: Hashable {
    case track
    case you

    var title: String {
        switch self {
        case .track: "Track"
        case .you: "You"
        }
    }

    var symbol: String {
        switch self {
        case .track: "figure.run"
        case .you: "person.fill"
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .preferredColorScheme(.dark)
}
