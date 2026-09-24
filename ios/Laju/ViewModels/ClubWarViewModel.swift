import Foundation

/// T4.2c: state for the Club War screen (product-spec.md §4.19). Scaffold — the T4.2b endpoints can't be
/// called live yet (T4.2a's migration isn't applied, and the Premium check always denies until T4.20), so
/// today this only runs against previews (`ClubWarPreviewData`, MOCK) and tests.
@MainActor
final class ClubWarViewModel: ObservableObject {
    @Published private(set) var myClubId: String?
    @Published private(set) var wars: [ClubWar] = []
    @Published private(set) var record: ClubWarRecordResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let apiClient: APIClient
    private let currentJWT: @Sendable () async throws -> String

    init(
        apiClient: APIClient = APIClient(),
        currentJWT: @escaping @Sendable () async throws -> String = {
            try await SupabaseConfig.client.auth.session.accessToken
        }
    ) {
        self.apiClient = apiClient
        self.currentJWT = currentJWT
    }

    var incomingChallenges: [ClubWar] {
        Self.incoming(in: wars, myClubId: myClubId)
    }

    var outgoingChallenges: [ClubWar] {
        Self.outgoing(in: wars, myClubId: myClubId)
    }

    var activeWar: ClubWar? {
        wars.first { $0.status == "active" }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let jwt = try await currentJWT()
            let list = try await apiClient.fetchClubWars(jwt: jwt)
            record = try await apiClient.fetchClubWarRecord(jwt: jwt)
            myClubId = list.clubId
            wars = list.wars
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// - Returns: `true` once the server accepted the challenge.
    func sendChallenge(to clubIds: [String]) async -> Bool {
        do {
            let jwt = try await currentJWT()
            _ = try await apiClient.createClubWar(invitedClubIds: clubIds, jwt: jwt)
            await load()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    func respond(to warId: String, accept: Bool) async {
        do {
            let jwt = try await currentJWT()
            _ = try await apiClient.respondToClubWar(warId: warId, accept: accept, jwt: jwt)
            await load()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Challenges waiting on *this* club's answer.
    static func incoming(in wars: [ClubWar], myClubId: String?) -> [ClubWar] {
        guard let myClubId else { return [] }
        return wars.filter { war in
            war.status == "pending" && war.clubs.contains { club in
                club.clubId == myClubId && club.role == "invited" && club.inviteStatus == "pending"
            }
        }
    }

    /// Challenges this club sent that are still waiting on the other clubs.
    static func outgoing(in wars: [ClubWar], myClubId: String?) -> [ClubWar] {
        guard let myClubId else { return [] }
        return wars.filter { war in
            war.status == "pending" && war.clubs.contains { $0.clubId == myClubId && $0.role == "inviter" }
        }
    }

    static func secondsRemaining(until end: Date, now: Date) -> Int {
        max(0, Int(end.timeIntervalSince(now).rounded(.down)))
    }

    /// `HH:MM:SS`, for the 48-hour countdown.
    static func countdownText(seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }

    private static let errorMessages: [String: String] = [
        "not_premium_club": "Club War butuh Club Premium — belum tersedia.",
        "not_in_club": "Kamu belum bergabung dengan club.",
        "not_club_admin": "Hanya owner atau admin club yang bisa melakukan ini.",
        "club_busy": "Salah satu club sedang dalam war lain.",
        "war_not_pending": "Tantangan ini sudah tidak menunggu jawaban.",
        "already_responded": "Club kamu sudah menjawab tantangan ini."
    ]

    static func message(for error: Error) -> String {
        if error is URLError {
            return "Tidak ada koneksi. Coba lagi saat online."
        }
        guard case let APIClientError.server(_, body) = error else {
            return "Club War belum bisa dimuat. Coba lagi."
        }
        let code = errorMessages.keys.first { body.contains("\"\($0)\"") }
        return code.flatMap { errorMessages[$0] } ?? "Club War belum bisa dimuat. Coba lagi."
    }

    #if DEBUG
        /// MOCK: preview-only state, never used by the app's real code paths.
        init(previewClubId: String, wars: [ClubWar], record: ClubWarRecordResponse?) {
            apiClient = APIClient()
            currentJWT = { "preview" }
            myClubId = previewClubId
            self.wars = wars
            self.record = record
        }
    #endif
}
