import Foundation

#if DEBUG
    /// MOCK — every value here is invented, for SwiftUI previews and the DEBUG-only scaffold (T4.2c).
    /// Replace with real data once T4.1b (club browse) exists and the war endpoints return club names.
    enum ClubWarPreviewData {
        struct ClubOption: Identifiable, Equatable {
            let id: String
            let name: String
        }

        static let myClubId = "club-laju"

        /// MOCK: there is no club browse/search endpoint until T4.1b, so the challenge picker lists these.
        static let challengeableClubs: [ClubOption] = [
            ClubOption(id: "club-rsb", name: "Rungkad Sunday Breakfast"),
            ClubOption(id: "club-kpr", name: "Kopi Pagi Runners"),
            ClubOption(id: "club-jlt", name: "Jogja Long Trot"),
            ClubOption(id: "club-mlm", name: "Lari Malam Mataram")
        ]

        /// MOCK: the war endpoints return club ids only, no names (open point in the T4.2b/T4.2c report).
        static func displayName(for clubId: String) -> String {
            if clubId == myClubId {
                return "Club Kamu"
            }
            return challengeableClubs.first { $0.id == clubId }?.name ?? "Club \(clubId.prefix(6))"
        }

        @MainActor
        static func viewModel(now: Date = Date()) -> ClubWarViewModel {
            ClubWarViewModel(
                previewClubId: myClubId,
                wars: wars(now: now),
                record: ClubWarRecordResponse(clubId: myClubId, wins: 3, losses: 1, netWins: 2)
            )
        }

        static func wars(now: Date) -> [ClubWar] {
            [
                war("war-active", startedHoursAgo: 28, now: now, clubs: [
                    ClubWarClub(clubId: myClubId, role: "inviter", inviteStatus: "accepted"),
                    ClubWarClub(clubId: "club-rsb", role: "invited", inviteStatus: "accepted")
                ]),
                war("war-incoming", startedHoursAgo: nil, now: now, clubs: [
                    ClubWarClub(clubId: "club-kpr", role: "inviter", inviteStatus: "accepted"),
                    ClubWarClub(clubId: myClubId, role: "invited", inviteStatus: "pending")
                ]),
                war("war-outgoing", startedHoursAgo: nil, now: now, clubs: [
                    ClubWarClub(clubId: myClubId, role: "inviter", inviteStatus: "accepted"),
                    ClubWarClub(clubId: "club-jlt", role: "invited", inviteStatus: "pending")
                ])
            ]
        }

        /// A pending war when `startedHoursAgo` is nil, otherwise an active one with its 48h end.
        private static func war(_ id: String, startedHoursAgo: Double?, now: Date, clubs: [ClubWarClub]) -> ClubWar {
            let hour: TimeInterval = 3600
            let startedAt = startedHoursAgo.map { now.addingTimeInterval(-$0 * hour) }
            return ClubWar(
                id: id,
                status: startedAt == nil ? "pending" : "active",
                challengeSentAt: now.addingTimeInterval(-2 * hour),
                acceptDeadlineAt: now.addingTimeInterval(22 * hour),
                startedAt: startedAt,
                endsAt: startedAt?.addingTimeInterval(48 * hour),
                endedAt: nil,
                winnerClubId: nil,
                winReason: nil,
                clubs: clubs
            )
        }
    }
#endif
