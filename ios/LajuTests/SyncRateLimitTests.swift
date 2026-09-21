import CoreData
@testable import Laju
import XCTest

/// T2.20a (SEC-9) client side: a `429` from the server's rate limiter ends the current sync batch instead of
/// firing the rest of the backlog at an account that is already over its limit. The runs stay `pendingSync`, so the
/// next cycle picks them up once the limit has lifted. Reuses `StubURLProtocol`/`FakePathMonitor` from
/// `SyncServiceTests.swift`.
@MainActor
final class SyncRateLimitTests: XCTestCase {
    private nonisolated static let created = Data("""
    {"run_id":"srv-1","status":"validated","flag_confidence":null,"final_points_awarded":7,
    "resolved_at":null,"anomaly_flags":[]}
    """.utf8)

    private nonisolated static let limited = Data(#"{"error":"rate_limited","retry_after_seconds":30}"#.utf8)

    private func makeContext() -> NSManagedObjectContext {
        StubURLProtocol.requestHandler = nil
        return PersistenceController(inMemory: true).container.viewContext
    }

    private func seedPendingRuns(in context: NSManagedObjectContext, count: Int) -> [Run] {
        (0 ..< count).map { index in
            let run = Run(context: context)
            run.id = UUID()
            // Oldest first, matching the queue's own ordering.
            run.startedAt = Date().addingTimeInterval(TimeInterval(-3600 + index * 600))
            run.endedAt = run.startedAt?.addingTimeInterval(300)
            run.distanceMeters = 500
            run.durationSeconds = 300
            run.estimatedPoints = 5
            run.syncStatus = "pendingSync"
            run.gpsRoute = try? JSONEncoder().encode([GPSPoint(
                lat: -6.2,
                lng: 106.8,
                timestamp: Date(),
                elevation: 45.0
            )])
            return run
        }
    }

    private func makeService(_ context: NSManagedObjectContext) -> SyncService {
        SyncService(
            context: context,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            pathMonitor: FakePathMonitor(),
            currentJWT: { "test-jwt" }
        )
    }

    func testRateLimitStopsTheBatchAfterTheFirstRefusal() async {
        let context = makeContext()
        let runs = seedPendingRuns(in: context, count: 5)
        try? context.save()
        let counter = Counter()
        StubURLProtocol.requestHandler = { _ in
            counter.increment()
            return (429, Self.limited)
        }

        await makeService(context).syncPendingRuns()

        XCTAssertEqual(counter.value, 1, "one refusal must end the batch — not 5 requests at a limited account")
        XCTAssertTrue(runs.allSatisfy { $0.syncStatus == "pendingSync" }, "nothing is lost or marked rejected")
    }

    func testRunsAreRetriedOnTheNextCycleOnceTheLimitLifts() async {
        let context = makeContext()
        let runs = seedPendingRuns(in: context, count: 3)
        try? context.save()
        let limited = Flag(true)
        StubURLProtocol.requestHandler = { _ in
            limited.value ? (429, Self.limited) : (201, Self.created)
        }
        let service = makeService(context)

        await service.syncPendingRuns()
        XCTAssertTrue(runs.allSatisfy { $0.syncStatus == "pendingSync" })

        limited.value = false
        await service.syncPendingRuns()
        XCTAssertTrue(
            runs.allSatisfy { $0.syncStatus == "synced" },
            "the whole backlog goes through after the window resets"
        )
    }

    func testRefusalMidBatchKeepsWhatWasAlreadySyncedAndStopsThere() async {
        let context = makeContext()
        let runs = seedPendingRuns(in: context, count: 4)
        try? context.save()
        let counter = Counter()
        StubURLProtocol.requestHandler = { _ in
            counter.increment() == 3 ? (429, Self.limited) : (201, Self.created)
        }

        await makeService(context).syncPendingRuns()

        XCTAssertEqual(counter.value, 3, "runs 1-2 accepted, run 3 refused, run 4 never sent")
        XCTAssertEqual(runs.map(\.syncStatus), ["synced", "synced", "pendingSync", "pendingSync"])
    }

    func testRateLimitIsNotAPermanentRejection() {
        XCTAssertFalse(SyncService.isPermanentRejection(SyncService.rateLimitedStatusCode))
        XCTAssertEqual(SyncService.rateLimitedStatusCode, 429)
    }
}

private final class Counter: @unchecked Sendable {
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

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool

    init(_ initial: Bool) {
        stored = initial
    }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }
}
