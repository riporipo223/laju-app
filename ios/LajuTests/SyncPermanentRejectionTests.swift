import CoreData
@testable import Laju
import XCTest

/// Regression tests for the permanent-rejection classification in `SyncService` (Fase 2 audit: 69 of the 127
/// runs on the test device were start/stop taps with distance 0 — the server answers them `400` forever, and
/// the queue used to resend every one of them on every cycle). Reuses `StubURLProtocol`/`FakePathMonitor`
/// from `SyncServiceTests.swift`.
@MainActor
final class SyncPermanentRejectionTests: XCTestCase {
    private func makeContext() -> NSManagedObjectContext {
        StubURLProtocol.requestHandler = nil
        return PersistenceController(inMemory: true).container.viewContext
    }

    private func seedPendingRun(
        in context: NSManagedObjectContext,
        gpsRoute: [GPSPoint] = [GPSPoint(lat: -6.2, lng: 106.8, timestamp: Date(), elevation: 45.0)],
        startedSecondsAgo: TimeInterval = 600
    ) -> Run {
        let run = Run(context: context)
        run.id = UUID()
        run.startedAt = Date().addingTimeInterval(-startedSecondsAgo)
        run.endedAt = Date()
        run.distanceMeters = 500
        run.durationSeconds = 300
        run.estimatedPoints = 5
        run.syncStatus = "pendingSync"
        run.gpsRoute = try? JSONEncoder().encode(gpsRoute)
        try? context.save()
        return run
    }

    private func makeService(_ context: NSManagedObjectContext) -> SyncService {
        SyncService(
            context: context,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            pathMonitor: FakePathMonitor(),
            currentJWT: { "test-jwt" }
        )
    }

    private nonisolated static let created = Data("""
    {"run_id":"srv-1","status":"validated","flag_confidence":null,"final_points_awarded":7,
    "resolved_at":null,"anomaly_flags":[]}
    """.utf8)

    private nonisolated static let badDistance = Data("""
    {"error":"invalid_request","message":"distance_meters must be greater than 0"}
    """.utf8)

    // MARK: - Permanent rejections leave the upload queue (Fase 2 audit: 69/127 device runs were retried forever)

    func testPermanentRejectionsAreMarkedAndNeverRetried() async {
        for status in [400, 413, 422] {
            let context = makeContext()
            let run = seedPendingRun(in: context)
            let counter = RequestCounter()
            StubURLProtocol.requestHandler = { _ in
                counter.increment()
                return (status, Self.badDistance)
            }
            let service = makeService(context)

            await service.syncPendingRuns()
            XCTAssertEqual(run.syncStatus, "rejectedPermanent", "HTTP \(status) is a permanent rejection")
            XCTAssertEqual(counter.value, 1)

            // The next cycles must not send it again — that was the bug: one wasted request per run per cycle.
            await service.syncPendingRuns()
            await service.syncPendingRuns()
            XCTAssertEqual(counter.value, 1, "HTTP \(status): a rejected-permanent run must never be resubmitted")
        }
    }

    func testRejectedRunStaysInLocalHistoryNothingIsDeleted() async throws {
        let context = makeContext()
        let run = seedPendingRun(in: context)
        run.distanceMeters = 0
        StubURLProtocol.requestHandler = { _ in (
            400,
            Self.badDistance
        ) }
        let service = makeService(context)

        await service.syncPendingRuns()

        let all = try context.fetch(Run.fetchRequest())
        XCTAssertEqual(all.count, 1, "the run must remain in local history")
        XCTAssertNotNil(all.first?.gpsRoute)
        XCTAssertNil(all.first?.serverRunId, "it never reached the server, so there is no server id")
    }

    func testTransientFailuresStayQueuedAndAreRetried() async {
        for status in [401, 409, 429, 500, 503] {
            let context = makeContext()
            let run = seedPendingRun(in: context)
            let counter = RequestCounter()
            StubURLProtocol.requestHandler = { _ in
                counter.increment()
                return (status, Data(#"{"error":"try later"}"#.utf8))
            }
            let service = makeService(context)

            await service.syncPendingRuns()
            await service.syncPendingRuns()

            XCTAssertEqual(run.syncStatus, "pendingSync", "HTTP \(status) is recoverable — must stay queued")
            XCTAssertEqual(counter.value, 2, "HTTP \(status) must be retried on the next cycle")
        }
    }

    func testOnePermanentRejectionDoesNotBlockTheRestOfTheBatch() async {
        let context = makeContext()
        let bad = seedPendingRun(in: context, startedSecondsAgo: 900)
        let good = seedPendingRun(in: context, startedSecondsAgo: 300)
        let counter = RequestCounter()
        StubURLProtocol.requestHandler = { _ in
            // Runs are submitted oldest-first: the first request is `bad`.
            if counter.increment() == 1 {
                return (400, Self.badDistance)
            }
            return (201, Self.created)
        }
        let service = makeService(context)

        await service.syncPendingRuns()

        XCTAssertEqual(bad.syncStatus, "rejectedPermanent")
        XCTAssertEqual(good.syncStatus, "synced")
    }

    func testEmptyRouteIsTakenOutOfTheQueueWithoutAnyRequest() async {
        let context = makeContext()
        let run = seedPendingRun(in: context, gpsRoute: [])
        StubURLProtocol.requestHandler = { _ in
            XCTFail("an empty route can never be accepted — no request should be made")
            return (201, Data())
        }
        let service = makeService(context)

        await service.syncPendingRuns()

        XCTAssertEqual(run.syncStatus, "rejectedPermanent")
    }

    func testPermanentRejectionClassification() {
        XCTAssertTrue(SyncService.isPermanentRejection(400))
        XCTAssertTrue(SyncService.isPermanentRejection(413))
        XCTAssertTrue(SyncService.isPermanentRejection(422))
        for recoverable in [401, 403, 404, 409, 429, 500, 502, 503] {
            XCTAssertFalse(SyncService.isPermanentRejection(recoverable), "\(recoverable) must stay retryable")
        }
    }
}

/// Thread-safe request counter for `@Sendable` stub handlers (a bare captured `var` is a Swift 6 error).
private final class RequestCounter: @unchecked Sendable {
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
