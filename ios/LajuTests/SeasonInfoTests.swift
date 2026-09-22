@testable import Laju
import SwiftUI
import XCTest

@MainActor
final class SeasonInfoTests: XCTestCase {
    /// Shape copied from the real `GET /api/seasons/active` response (database-api-spec.md §2.5).
    private nonisolated static let liveShapedBody = Data("""
    {"id":"s1","name":"Season 3 — 2026","start_at":"2026-07-01T00:00:00.000000+00:00",
    "end_at":"2026-09-30T23:59:59.000000+00:00","status":"active","days_remaining":22,
    "me":{"season_points":312,"league":"gold"}}
    """.utf8)

    private nonisolated static let noMeBody = Data("""
    {"id":"s2","name":"Season 4","start_at":"2026-10-01T00:00:00.000000+00:00",
    "end_at":"2026-12-31T23:59:59.000000+00:00","status":"active","days_remaining":5,"me":null}
    """.utf8)

    private func makeViewModel(jwt: @escaping @Sendable () async throws -> String = { "jwt" }) -> SeasonInfoViewModel {
        StubURLProtocol.requestHandler = nil
        return SeasonInfoViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: jwt)
    }

    // MARK: - Decoding the real response shape

    func testDecodesLiveShapedResponseIncludingMeAndTimestamps() async throws {
        StubURLProtocol.requestHandler = { _ in (200, Self.liveShapedBody) }
        let response = try await APIClient(session: StubURLProtocol.makeSession())
            .fetchActiveSeason(jwt: "jwt")

        XCTAssertEqual(response.name, "Season 3 — 2026")
        XCTAssertEqual(response.daysRemaining, 22)
        XCTAssertEqual(response.me, ActiveSeasonMe(seasonPoints: 312, league: "gold"))
        XCTAssertNotNil(response.startAt)
        XCTAssertNotNil(response.endAt)
    }

    func testRequestSendsBearerToken() async throws {
        let captured = CapturedActiveSeasonRequest()
        StubURLProtocol.requestHandler = { request in
            captured.set(request)
            return (200, Self.noMeBody)
        }
        _ = try await APIClient(session: StubURLProtocol.makeSession()).fetchActiveSeason(jwt: "abc")

        let request = try XCTUnwrap(captured.value)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        XCTAssertTrue(request.url?.path.hasSuffix("api/seasons/active") ?? false)
    }

    func testNullMeDecodes() async throws {
        StubURLProtocol.requestHandler = { _ in (200, Self.noMeBody) }
        let response = try await APIClient(session: StubURLProtocol.makeSession())
            .fetchActiveSeason(jwt: "jwt")
        XCTAssertNil(response.me)
    }

    // MARK: - View model

    func testLoadPopulatesSeason() async {
        let viewModel = makeViewModel()
        StubURLProtocol.requestHandler = { _ in (200, Self.liveShapedBody) }
        await viewModel.load()
        XCTAssertEqual(viewModel.season?.name, "Season 3 — 2026")
        XCTAssertFalse(viewModel.loadFailed)
    }

    func testFailureBeforeAnySuccessLeavesNoSeasonAndFlagsFailure() async {
        let viewModel = makeViewModel()
        StubURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        await viewModel.load()
        XCTAssertNil(viewModel.season)
        XCTAssertTrue(viewModel.loadFailed)
    }

    func testFailureAfterSuccessKeepsTheLastSeasonAndRecoversOnNextSuccess() async {
        let viewModel = makeViewModel()
        StubURLProtocol.requestHandler = { _ in (200, Self.liveShapedBody) }
        await viewModel.load()

        StubURLProtocol.requestHandler = { _ in (500, Data()) }
        await viewModel.load()
        XCTAssertNotNil(viewModel.season, "a later failure must not blank a season already on screen")
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

    // MARK: - Countdown ticks between loads (AC: "updates as time passes")

    func testLiveDaysRemainingRecomputesFromEndAtAsTimeMovesForward() async throws {
        let viewModel = makeViewModel()
        StubURLProtocol.requestHandler = { _ in (200, Self.liveShapedBody) }
        await viewModel.load()

        let endAt = try XCTUnwrap(viewModel.season?.endAt)
        XCTAssertEqual(viewModel.liveDaysRemaining(now: endAt.addingTimeInterval(-1 * 86400 - 1)), 2)
        XCTAssertEqual(viewModel.liveDaysRemaining(now: endAt.addingTimeInterval(-1)), 1)
        XCTAssertEqual(viewModel.liveDaysRemaining(now: endAt), 0)
        XCTAssertEqual(viewModel.liveDaysRemaining(now: endAt.addingTimeInterval(3600)), 0, "never goes negative past end")
    }

    func testLiveDaysRemainingIsNilBeforeAnyLoad() {
        let viewModel = makeViewModel()
        XCTAssertNil(viewModel.liveDaysRemaining(now: Date()))
    }

    // MARK: - The real view renders (written to disk so it can be looked at, not just asserted non-nil)

    func testContentViewRendersCountdownAndMeCard() throws {
        let season = ActiveSeasonResponse(
            id: "s1",
            name: "Season 3 — 2026",
            startAt: Date(timeIntervalSince1970: 1_700_000_000),
            endAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: "active",
            daysRemaining: 22,
            me: ActiveSeasonMe(seasonPoints: 312, league: "gold")
        )
        let view = ZStack {
            LajuColor.background
            SeasonInfoContent(season: season, daysRemaining: 22).padding()
        }
        .frame(width: 402)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertGreaterThan(image.size.height, 150)
        try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: "/tmp/laju_season_info_content.png"))
    }
}

private final class CapturedActiveSeasonRequest: @unchecked Sendable {
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
