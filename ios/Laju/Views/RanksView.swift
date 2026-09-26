import SwiftUI

/// Ranks tab root (2026-09-24 nav restructure, Bagian B item 5): a segmented control switching between three
/// leaderboards. Only "Pengguna" (the existing global `LeaderboardView`, T2.20) is real — Club and Club War
/// leaderboards have no owning task/endpoint yet (checked: no `club-leaderboard`/`ClubLeaderboard` code
/// anywhere in `backend/` or `ios/`, and `tasks/README.md` has no T4.17 work started). Tracked as a gap, not
/// built here per the PM's own instruction not to force it.
struct RanksView: View {
    private enum Board: String, CaseIterable, Identifiable {
        case users, club, clubWar

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .users: "Pengguna"
            case .club: "Circle"
            case .clubWar: "Club War"
            }
        }
    }

    @State private var board: Board = .users

    var body: some View {
        VStack(spacing: 0) {
            Picker("Papan", selection: $board) {
                ForEach(Board.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            switch board {
            case .users:
                LeaderboardView()
            case .club:
                ComingSoonView(
                    systemImage: "shield.lefthalf.filled",
                    title: "Circle Leaderboard belum ada",
                    message: "Circle (T4.1) dan leaderboard-nya belum dibangun. Lari, poin, dan level tetap "
                        + "berjalan seperti biasa."
                )
                .navigationTitle("Ranks")
                .toolbarColorScheme(.dark, for: .navigationBar)
            case .clubWar:
                ComingSoonView(
                    systemImage: "flag.2.crossed.fill",
                    title: "Club War Leaderboard belum ada",
                    message: "Club War (T4.2) belum punya papan peringkat sendiri. Lari, poin, dan level tetap "
                        + "berjalan seperti biasa."
                )
                .navigationTitle("Ranks")
                .toolbarColorScheme(.dark, for: .navigationBar)
            }
        }
        .background(LajuColor.background.ignoresSafeArea())
    }
}

#Preview {
    NavigationStack {
        RanksView()
    }
    .preferredColorScheme(.dark)
}
