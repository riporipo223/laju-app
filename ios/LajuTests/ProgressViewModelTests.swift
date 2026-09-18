@testable import Laju
import XCTest

@MainActor
final class ProgressViewModelTests: XCTestCase {
    /// `nonisolated static`, not an instance method — matching `SyncServiceTests`'s
    /// `successResponseBody`/`flaggedResponseBody` precedent, since a `@Sendable` stub closure cannot
    /// capture `self` (this class is `@MainActor`-isolated, not `Sendable`).
    private nonisolated static func progressResponseBody(
        totalPoints: Int = 1240,
        currentLevel: Int = 6,
        pointsToNextLevel: Int = 260,
        trustScore: Double = 0.98
    ) -> Data {
        let json = """
        {
          "total_points": \(totalPoints),
          "current_level": \(currentLevel),
          "points_to_next_level": \(pointsToNextLevel),
          "trust_score": \(trustScore)
        }
        """
        return Data(json.utf8)
    }

    override func setUp() {
        StubURLProtocol.requestHandler = nil
    }

    // MARK: - DoD: screen shows server-derived values when online/synced

    func testRefreshPopulatesServerProgressFromResponse() async {
        StubURLProtocol.requestHandler = { _ in (200, Self.progressResponseBody()) }
        let viewModel = ProgressViewModel(
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: { "test-jwt" }
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.serverProgress, ProgressResponse(
            totalPoints: 1240, currentLevel: 6, pointsToNextLevel: 260, trustScore: 0.98
        ))
    }

    // MARK: - DoD: gracefully falls back to local estimate when offline (no broken UI state)

    func testRefreshLeavesServerProgressNilOnNetworkFailure() async {
        StubURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let viewModel = ProgressViewModel(
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: { "test-jwt" }
        )

        await viewModel.refresh()

        let message = "a failed fetch must never fabricate a value — the caller's fallback depends on nil"
        XCTAssertNil(viewModel.serverProgress, message)
    }

    func testRefreshLeavesServerProgressNilWhenNotSignedIn() async {
        StubURLProtocol.requestHandler = { _ in
            XCTFail("should never reach the network without a session")
            return (200, Data())
        }
        let viewModel = ProgressViewModel(
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: { throw APIClientError.notAuthenticated }
        )

        await viewModel.refresh()

        XCTAssertNil(viewModel.serverProgress)
    }

    func testRefreshPreservesLastKnownGoodValueOnASubsequentFailure() async {
        StubURLProtocol.requestHandler = { _ in (200, Self.progressResponseBody()) }
        let viewModel = ProgressViewModel(
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: { "test-jwt" }
        )
        await viewModel.refresh()
        XCTAssertNotNil(viewModel.serverProgress)

        StubURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        await viewModel.refresh()

        let message = "a later failure (e.g. going offline) must not wipe an already-fetched value back to nil"
        XCTAssertNotNil(viewModel.serverProgress, message)
    }

    // MARK: - DoD: refresh() is callable from outside the screen and genuinely re-fetches

    func testRefreshIsCallableDirectlyAndReFetchesEachCall() async {
        let counter = CallCounter()
        StubURLProtocol.requestHandler = { _ in
            let call = counter.increment()
            return (200, Self.progressResponseBody(totalPoints: call == 1 ? 100 : 500))
        }
        let viewModel = ProgressViewModel(
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: { "test-jwt" }
        )

        await viewModel.refresh()
        XCTAssertEqual(viewModel.serverProgress?.totalPoints, 100)

        // Called directly a second time, independent of any screen appearing — this is exactly what
        // T2.14d's future reconciliation loop needs to do.
        await viewModel.refresh()
        let message = "a direct second call must genuinely re-fetch, not return a cached value"
        XCTAssertEqual(viewModel.serverProgress?.totalPoints, 500, message)
        XCTAssertEqual(counter.value, 2)
    }
}

/// Thread-safe call counter for stub handlers — `@Sendable` closures can't capture a mutable `var` directly
/// under Swift 6 strict concurrency, same reasoning as `FakePathMonitor`'s `@unchecked Sendable` above.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}
