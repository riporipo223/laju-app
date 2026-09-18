@testable import Laju
import SwiftUI
import XCTest

@MainActor
final class LeaderboardTests: XCTestCase {
    /// Shape copied from a real `GET /api/leaderboard` response (deployed T2.19) — note `computed_at` carries
    /// microseconds and a `+00:00` offset, exactly what PostgREST emits.
    private nonisolated static let liveShapedBody = Data("""
    {"season_id":"0a23423a-20b4-4b86-a65f-4d73097112f6","scope":"global","scope_id":null,
    "computed_at":"2026-09-18T21:22:04.515449+00:00","insufficient_data":false,
    "entries":[
      {"rank":1,"user_id":"u1","username":"N top","points":500},
      {"rank":2,"user_id":"u2","username":null,"points":300}
    ],
    "me":{"rank":47,"points":120}}
    """.utf8)

    private nonisolated static let noMeBody = Data("""
    {"season_id":"s","scope":"global","scope_id":null,"computed_at":null,"insufficient_data":false,
    "entries":[],"me":null}
    """.utf8)

    private func makeViewModel(jwt: @escaping @Sendable () async throws -> String = { "jwt" }) -> LeaderboardViewModel {
        StubURLProtocol.requestHandler = nil
        return LeaderboardViewModel(
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: jwt,
            limit: 50
        )
    }

    // MARK: - Decoding the real response shape

    func testDecodesLiveShapedResponseIncludingMicrosecondTimestampAndOwnRankOutsideTopN() async throws {
        StubURLProtocol.requestHandler = { _ in (200, Self.liveShapedBody) }
        let response = try await APIClient(session: StubURLProtocol.makeSession())
            .fetchLeaderboard(limit: 50, jwt: "jwt")

        XCTAssertNotNil(response.computedAt, "microsecond computed_at must decode")
        XCTAssertEqual(response.entries.map(\.rank), [1, 2])
        XCTAssertNil(response.entries[1].username, "a null name must decode, not fail the whole board")
        XCTAssertEqual(response.me, LeaderboardMe(rank: 47, points: 120))
        XCTAssertFalse(
            response.entries.contains { $0.rank == response.me?.rank },
            "AC 4.5.1: own position is present even though it is outside the top-N list"
        )
    }

    func testRequestSendsGlobalScopeLimitAndBearerToken() async throws {
        let captured = CapturedRequest()
        StubURLProtocol.requestHandler = { request in
            captured.set(request)
            return (200, Self.noMeBody)
        }
        _ = try await APIClient(session: StubURLProtocol.makeSession()).fetchLeaderboard(limit: 25, jwt: "abc")

        let request = try XCTUnwrap(captured.value)
        let items = try URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "scope" }?.value, "global")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "25")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
    }

    func testNullMeAndNullComputedAtDecode() async throws {
        StubURLProtocol.requestHandler = { _ in (200, Self.noMeBody) }
        let response = try await APIClient(session: StubURLProtocol.makeSession())
            .fetchLeaderboard(limit: 50, jwt: "jwt")
        XCTAssertNil(response.me)
        XCTAssertNil(response.computedAt)
    }

    // MARK: - View model

    func testLoadPopulatesResponse() async {
        let viewModel = makeViewModel()
        StubURLProtocol.requestHandler = { _ in (200, Self.liveShapedBody) }
        await viewModel.load()
        XCTAssertEqual(viewModel.response?.entries.count, 2)
        XCTAssertFalse(viewModel.loadFailed)
    }

    func testFailureBeforeAnySuccessLeavesNoResponseAndFlagsFailure() async {
        let viewModel = makeViewModel()
        StubURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        await viewModel.load()
        XCTAssertNil(viewModel.response)
        XCTAssertTrue(viewModel.loadFailed)
    }

    func testFailureAfterSuccessKeepsTheLastBoardAndRecoversOnNextSuccess() async {
        let viewModel = makeViewModel()
        StubURLProtocol.requestHandler = { _ in (200, Self.liveShapedBody) }
        await viewModel.load()

        StubURLProtocol.requestHandler = { _ in (500, Data()) }
        await viewModel.load()
        XCTAssertNotNil(viewModel.response, "a later failure must not blank a board already on screen")
        XCTAssertTrue(viewModel.loadFailed)

        StubURLProtocol.requestHandler = { _ in (200, Self.liveShapedBody) }
        await viewModel.load()
        XCTAssertFalse(viewModel.loadFailed)
    }

    func testSignedOutFailsWithoutTouchingTheNetwork() async {
        let viewModel = makeViewModel(jwt: { throw APIClientError.notAuthenticated })
        StubURLProtocol.requestHandler = { _ in
            XCTFail("no session — must not reach the network")
            return (200, Data())
        }
        await viewModel.load()
        XCTAssertTrue(viewModel.loadFailed)
    }

    // MARK: - Staleness (AC 4.5.2)

    func testFreshnessText() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func text(_ ageSeconds: TimeInterval) -> String {
            LeaderboardFreshness.text(computedAt: now.addingTimeInterval(-ageSeconds), now: now)
        }
        XCTAssertEqual(text(20), "Diperbarui baru saja")
        XCTAssertEqual(text(7 * 60), "Diperbarui 7 menit lalu")
        XCTAssertEqual(text(14 * 60 + 59), "Diperbarui 14 menit lalu")
        XCTAssertEqual(text(2 * 3600 + 30), "Diperbarui 2 jam lalu — data mungkin belum terbarui")
        XCTAssertEqual(LeaderboardFreshness.text(computedAt: nil, now: now), "Leaderboard belum dihitung")
    }

    func testStalenessOnlyFlagsPastTheHealthyCycle() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(LeaderboardFreshness.isStale(computedAt: now.addingTimeInterval(-15 * 60), now: now))
        XCTAssertFalse(LeaderboardFreshness.isStale(computedAt: now.addingTimeInterval(-20 * 60), now: now))
        XCTAssertTrue(LeaderboardFreshness.isStale(computedAt: now.addingTimeInterval(-20 * 60 - 1), now: now))
        XCTAssertFalse(LeaderboardFreshness.isStale(computedAt: nil, now: now))
    }

    // MARK: - The real view renders (written to disk so it can be looked at, not just asserted non-nil)

    func testContentViewRendersTopNAndOwnPositionOutsideIt() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let response = LeaderboardResponse(
            seasonId: "s",
            computedAt: now.addingTimeInterval(-7 * 60),
            insufficientData: false,
            entries: (1 ... 6).map {
                LeaderboardEntry(rank: $0, userId: "u\($0)", username: "Pelari \($0)", points: 1000 - $0 * 110)
            },
            me: LeaderboardMe(rank: 47, points: 120)
        )
        let view = ZStack {
            LajuColor.background
            LeaderboardContent(response: response, now: now).padding()
        }
        .frame(width: 402)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertGreaterThan(image.size.height, 300)
        try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: "/tmp/laju_leaderboard_content.png"))
    }
}

private final class CapturedRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?

    func set(_ request: URLRequest) {
        lock.lock()
        stored = request
        lock.unlock()
    }

    var value: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
