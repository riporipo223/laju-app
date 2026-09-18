import CoreData
@testable import Laju
import XCTest

/// Intercepts every request on a test-configured `URLSession` — this codebase had no URLSession stubbing
/// harness before T2.14, so this is the first one; `requestHandler` is set per-test.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.unknown))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// Test double for `PathMonitoring` — captures the handler `SyncService.init` registers so a test can
/// simulate a connectivity transition without touching real `NWPathMonitor` state.
final class FakePathMonitor: PathMonitoring, @unchecked Sendable {
    private(set) var onUpdateHandler: (@Sendable (Bool) -> Void)?
    private(set) var cancelCallCount = 0

    func start(onUpdate: @escaping @Sendable (Bool) -> Void) {
        onUpdateHandler = onUpdate
    }

    func cancel() {
        cancelCallCount += 1
    }

    func simulateConnectivityRestored() {
        onUpdateHandler?(true)
    }
}

@MainActor
final class SyncServiceTests: XCTestCase {
    private func makeContext() -> NSManagedObjectContext {
        let controller = PersistenceController(inMemory: true)
        StubURLProtocol.requestHandler = nil
        return controller.container.viewContext
    }

    private func seedPendingRun(
        in context: NSManagedObjectContext,
        syncStatus: String = "pendingSync",
        endedAt: Date? = Date(),
        gpsRoute: [GPSPoint] = [GPSPoint(lat: -6.2, lng: 106.8, timestamp: Date(), elevation: 45.0)]
    ) -> Run {
        let run = Run(context: context)
        run.id = UUID()
        run.startedAt = Date().addingTimeInterval(-600)
        run.endedAt = endedAt
        run.distanceMeters = 500
        run.durationSeconds = 300
        run.estimatedPoints = 5
        run.syncStatus = syncStatus
        run.gpsRoute = try? JSONEncoder().encode(gpsRoute)
        try? context.save()
        return run
    }

    private nonisolated static func successResponseBody(runId: String = UUID().uuidString) -> Data {
        let json = """
        {
          "run_id": "\(runId)",
          "status": "validated",
          "flag_confidence": null,
          "final_points_awarded": 7,
          "resolved_at": "2026-09-18T04:26:30.381Z",
          "anomaly_flags": []
        }
        """
        return Data(json.utf8)
    }

    private nonisolated static func flaggedResponseBody(runId: String) -> Data {
        let json = """
        {
          "run_id": "\(runId)",
          "status": "flagged",
          "flag_confidence": "low",
          "final_points_awarded": 2,
          "resolved_at": null,
          "anomaly_flags": ["pace_cap_exceeded"]
        }
        """
        return Data(json.utf8)
    }

    // MARK: - DoD: a run recorded fully offline syncs automatically once connectivity returns

    func testSyncsAutomaticallyWhenConnectivityReturns() async throws {
        let context = makeContext()
        let run = seedPendingRun(in: context)
        let responseRunId = UUID().uuidString
        StubURLProtocol.requestHandler = { _ in (201, Self.successResponseBody(runId: responseRunId)) }
        let fakeMonitor = FakePathMonitor()

        // Held in `service` (not discarded via `_ =`) — SyncService only holds a `weak self` in the path
        // monitor's callback, so a discarded instance would be deallocated before
        // `simulateConnectivityRestored()` below ever fires it.
        let service = SyncService(
            context: context,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            pathMonitor: fakeMonitor,
            currentJWT: { "test-jwt" }
        )

        XCTAssertNotNil(fakeMonitor.onUpdateHandler, "SyncService must register a connectivity handler on init")
        fakeMonitor.simulateConnectivityRestored()

        // The connectivity handler spawns a detached Task (real NWPathMonitor callbacks aren't async) —
        // poll with a timeout rather than assume a fixed delay.
        try await pollUntil(timeout: 2.0) {
            context.refresh(run, mergeChanges: true)
            return run.syncStatus == "synced"
        }

        XCTAssertEqual(run.syncStatus, "synced")
        XCTAssertEqual(run.serverRunId, responseRunId)
        _ = service // keep alive until here — see the comment at its declaration above
    }

    // MARK: - DoD: local estimatedPoints replaced by server final_points_awarded after sync

    func testFinalPointsAwardedPopulatedFromServerResponse() async {
        let context = makeContext()
        let run = seedPendingRun(in: context)
        StubURLProtocol.requestHandler = { _ in (201, Self.successResponseBody()) }
        let service = SyncService(
            context: context,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            pathMonitor: FakePathMonitor(),
            currentJWT: { "test-jwt" }
        )

        await service.syncPendingRuns()

        XCTAssertEqual(run.finalPointsAwarded, 7)
    }

    // MARK: - DoD: repeated sync failures do not drop the run — stays queued, retried, never discarded

    func testFailedSyncLeavesRunQueuedForRetry() async {
        let context = makeContext()
        let run = seedPendingRun(in: context)
        StubURLProtocol.requestHandler = { _ in (500, Data(#"{"error":"boom"}"#.utf8)) }
        let service = SyncService(
            context: context,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            pathMonitor: FakePathMonitor(),
            currentJWT: { "test-jwt" }
        )

        await service.syncPendingRuns()
        XCTAssertEqual(run.syncStatus, "pendingSync", "a failed sync must not change syncStatus")
        XCTAssertNil(run.serverRunId, "a failed sync must not partially populate server fields")

        // Retry, now succeeding — proves the run genuinely remained queryable/eligible after the failure,
        // not silently dropped from the sync set.
        StubURLProtocol.requestHandler = { _ in (201, Self.successResponseBody()) }
        await service.syncPendingRuns()
        XCTAssertEqual(run.syncStatus, "synced")
    }

    func testNetworkErrorAlsoLeavesRunQueuedForRetry() async {
        let context = makeContext()
        let run = seedPendingRun(in: context)
        StubURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let service = SyncService(
            context: context,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            pathMonitor: FakePathMonitor(),
            currentJWT: { "test-jwt" }
        )

        await service.syncPendingRuns()
        XCTAssertEqual(run.syncStatus, "pendingSync")
    }

    // MARK: - DoD: after a successful sync, serverRunId/serverStatus/flagConfidence/anomalyFlags/resolvedAt

    // are populated — verified specifically for a flagged response.

    func testFlaggedResponsePopulatesAllServerFields() async {
        let context = makeContext()
        let run = seedPendingRun(in: context)
        let responseRunId = UUID().uuidString
        StubURLProtocol.requestHandler = { _ in (201, Self.flaggedResponseBody(runId: responseRunId)) }
        let service = SyncService(
            context: context,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            pathMonitor: FakePathMonitor(),
            currentJWT: { "test-jwt" }
        )

        await service.syncPendingRuns()

        XCTAssertEqual(run.syncStatus, "synced")
        XCTAssertEqual(run.serverRunId, responseRunId)
        XCTAssertEqual(run.serverStatus, "flagged")
        XCTAssertEqual(run.flagConfidence, "low")
        XCTAssertEqual(run.finalPointsAwarded, 2)
        let resolvedAtMessage = "a still-flagged run's resolved_at is null — must not default to anything else"
        XCTAssertNil(run.resolvedAt, resolvedAtMessage)
        let flags = (try? JSONDecoder().decode([String].self, from: run.anomalyFlags ?? Data())) ?? []
        XCTAssertEqual(flags, ["pace_cap_exceeded"])
    }

    // MARK: - Supporting behavior

    func testDoesNotAttemptToSyncAnUnfinishedRun() async {
        let context = makeContext()
        let run = seedPendingRun(in: context, endedAt: nil)
        StubURLProtocol.requestHandler = { _ in
            XCTFail("should never be called for a run with endedAt == nil")
            return (201, Data())
        }
        let service = SyncService(
            context: context,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            pathMonitor: FakePathMonitor(),
            currentJWT: { "test-jwt" }
        )

        await service.syncPendingRuns()
        XCTAssertEqual(run.syncStatus, "pendingSync")
    }

    func testAlreadySyncedRunIsNotResubmitted() async {
        let context = makeContext()
        _ = seedPendingRun(in: context, syncStatus: "synced")
        StubURLProtocol.requestHandler = { _ in
            XCTFail("should never be called for an already-synced run")
            return (201, Data())
        }
        let service = SyncService(
            context: context,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            pathMonitor: FakePathMonitor(),
            currentJWT: { "test-jwt" }
        )

        await service.syncPendingRuns()
    }

    func testMissingSessionAbortsWithoutTouchingRuns() async {
        let context = makeContext()
        let run = seedPendingRun(in: context)
        StubURLProtocol.requestHandler = { _ in
            XCTFail("should never reach the network without a session")
            return (201, Data())
        }
        let service = SyncService(
            context: context,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            pathMonitor: FakePathMonitor(),
            currentJWT: { throw APIClientError.notAuthenticated }
        )

        await service.syncPendingRuns()
        XCTAssertEqual(run.syncStatus, "pendingSync")
    }

    // MARK: - Helpers

    private func pollUntil(timeout: TimeInterval, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition not met within \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
