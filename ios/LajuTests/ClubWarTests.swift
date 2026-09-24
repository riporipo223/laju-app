@testable import Laju
import XCTest

/// T4.2c: Club War wire decoding, request shape, and the view model's pure rules. The JSON below is exactly what
/// the T4.2b backend's `serializeWar` / record route produce. Reuses `StubURLProtocol` from `SyncServiceTests.swift`.
@MainActor
final class ClubWarTests: XCTestCase {
    private let listJSON = """
    {"club_id":"A","wars":[{"id":"w1","status":"active","challenge_sent_at":"2026-10-01T00:00:00.000Z",
    "accept_deadline_at":"2026-10-02T00:00:00.000Z","started_at":"2026-10-01T06:00:00.000Z",
    "ends_at":"2026-10-03T06:00:00.000Z","ended_at":null,"winner_club_id":null,"win_reason":null,
    "clubs":[{"club_id":"A","role":"inviter","invite_status":"accepted"},
    {"club_id":"B","role":"invited","invite_status":"accepted"}]}]}
    """

    func testDecodesTheBackendListShape() throws {
        let decoded = try RunSubmissionCoding.makeDecoder().decode(ClubWarListResponse.self, from: Data(listJSON.utf8))
        XCTAssertEqual(decoded.clubId, "A")
        let war = try XCTUnwrap(decoded.wars.first)
        XCTAssertEqual(war.status, "active")
        XCTAssertNil(war.endedAt)
        let startedAt = try XCTUnwrap(war.startedAt)
        let endsAt = try XCTUnwrap(war.endsAt)
        XCTAssertEqual(endsAt.timeIntervalSince(startedAt), 48 * 3600)
        XCTAssertEqual(war.clubs.map(\.role), ["inviter", "invited"])
    }

    func testDecodesTheRecordShape() throws {
        let json = #"{"club_id":"A","wins":3,"losses":5,"net_wins":-2}"#
        let record = try RunSubmissionCoding.makeDecoder().decode(ClubWarRecordResponse.self, from: Data(json.utf8))
        XCTAssertEqual(record, ClubWarRecordResponse(clubId: "A", wins: 3, losses: 5, netWins: -2))
    }

    func testCreateSendsInvitedClubIdsWithTheBearerToken() async throws {
        let box = ClubWarRequestBox()
        StubURLProtocol.requestHandler = { request in
            box.record(request)
            return (201, Data(#"{"war_id":"w9","status":"pending"}"#.utf8))
        }
        let client = APIClient(session: StubURLProtocol.makeSession())
        let response = try await client.createClubWar(invitedClubIds: ["B", "C"], jwt: "jwt-1")

        XCTAssertEqual(response, ClubWarStatusResponse(warId: "w9", status: "pending"))
        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/club-wars")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-1")
    }

    func testTheDeniedPremiumCheckBecomesAReadableMessage() {
        let error = APIClientError.server(statusCode: 403, body: #"{"error":"not_premium_club"}"#)
        XCTAssertEqual(ClubWarViewModel.message(for: error), "Club War butuh Club Premium — belum tersedia.")
        XCTAssertEqual(
            ClubWarViewModel.message(for: APIClientError.server(statusCode: 409, body: #"{"error":"club_busy"}"#)),
            "Salah satu club sedang dalam war lain."
        )
        XCTAssertEqual(
            ClubWarViewModel.message(for: URLError(.notConnectedToInternet)),
            "Tidak ada koneksi. Coba lagi saat online."
        )
        XCTAssertEqual(
            ClubWarViewModel.message(for: APIClientError.server(statusCode: 500, body: "")),
            "Club War belum bisa dimuat. Coba lagi."
        )
    }

    func testIncomingIsOnlyPendingWarsAwaitingThisClubsAnswer() {
        let otherInviter = club("X", "inviter", "accepted")
        let meInvitedPending = club("A", "invited", "pending")
        let wars = [
            war("in", status: "pending", clubs: [otherInviter, meInvitedPending]),
            war("answered", status: "pending", clubs: [otherInviter, club("A", "invited", "accepted")]),
            war("mine", status: "pending", clubs: [club("A", "inviter", "accepted"), club("Y", "invited", "pending")]),
            war("over", status: "dissolved", clubs: [otherInviter, meInvitedPending])
        ]
        XCTAssertEqual(ClubWarViewModel.incoming(in: wars, myClubId: "A").map(\.id), ["in"])
        XCTAssertEqual(ClubWarViewModel.outgoing(in: wars, myClubId: "A").map(\.id), ["mine"])
        XCTAssertTrue(ClubWarViewModel.incoming(in: wars, myClubId: nil).isEmpty)
    }

    func testCountdownNeverGoesNegativeAndFormatsHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ClubWarViewModel.secondsRemaining(until: now.addingTimeInterval(90), now: now), 90)
        XCTAssertEqual(ClubWarViewModel.secondsRemaining(until: now.addingTimeInterval(-5), now: now), 0)
        XCTAssertEqual(ClubWarViewModel.countdownText(seconds: 47 * 3600 + 59 * 60 + 58), "47:59:58")
        XCTAssertEqual(ClubWarViewModel.countdownText(seconds: 0), "00:00:00")
    }

    private func club(_ clubId: String, _ role: String, _ inviteStatus: String) -> ClubWarClub {
        ClubWarClub(clubId: clubId, role: role, inviteStatus: inviteStatus)
    }

    private func war(_ id: String, status: String, clubs: [ClubWarClub]) -> ClubWar {
        ClubWar(
            id: id,
            status: status,
            challengeSentAt: Date(),
            acceptDeadlineAt: Date(),
            startedAt: nil,
            endsAt: nil,
            endedAt: nil,
            winnerClubId: nil,
            winReason: nil,
            clubs: clubs
        )
    }
}

/// Captures the request the stub saw — the handler is `@Sendable`, so it can't write to a captured `var`.
private final class ClubWarRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        stored = request
    }
}
