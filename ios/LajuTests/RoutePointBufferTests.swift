import CoreData
@testable import Laju
import XCTest

/// CQ-2 regression tests (code-quality-audit.md): `RoutePointBuffer.flush` used to have two silent-total-loss
/// paths — an unreadable existing `run.gpsRoute` decoded as `[]` and got overwritten with just the pending
/// points (truncating the route), and an encode failure `try?`'d into `nil`, wiping the route entirely while
/// `pending` was cleared on the very next line regardless of success. These tests assert the fixed behavior:
/// a flush either genuinely succeeds, or it fails loudly and leaves both `run.gpsRoute` and `pending` untouched
/// so nothing already recorded is lost.
final class RoutePointBufferTests: XCTestCase {
    private func makeRun(in context: NSManagedObjectContext) -> Run {
        let run = Run(context: context)
        run.id = UUID()
        run.startedAt = Date()
        return run
    }

    private func point(lat: Double = -7.7057, lng: Double = 110.4084, elevation: Double = 100) -> GPSPoint {
        GPSPoint(lat: lat, lng: lng, timestamp: Date(), elevation: elevation)
    }

    func testFlushWithNothingPendingIsANoOp() {
        let controller = PersistenceController(inMemory: true)
        let run = makeRun(in: controller.container.viewContext)
        let buffer = RoutePointBuffer()

        let result = buffer.flush(into: run)

        XCTAssertEqual(result, .success)
        XCTAssertNil(run.gpsRoute, "Nothing was pending, so gpsRoute must stay untouched")
    }

    func testFlushOnAFreshRunPersistsThePendingPoints() {
        let controller = PersistenceController(inMemory: true)
        let run = makeRun(in: controller.container.viewContext)
        let buffer = RoutePointBuffer()
        buffer.append(point())
        buffer.append(point(lat: -7.7060))

        let result = buffer.flush(into: run)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(buffer.count, 0, "pending must be cleared once the merge is actually persisted")
        let route = GPSPoint.decodeRoute(from: run.gpsRoute)
        XCTAssertEqual(route.count, 2)
    }

    func testASecondFlushAppendsToTheFirstRatherThanReplacingIt() {
        let controller = PersistenceController(inMemory: true)
        let run = makeRun(in: controller.container.viewContext)
        let buffer = RoutePointBuffer()

        buffer.append(point())
        buffer.flush(into: run)
        buffer.append(point(lat: -7.7099))
        buffer.flush(into: run)

        let route = GPSPoint.decodeRoute(from: run.gpsRoute)
        XCTAssertEqual(route.count, 2, "the second flush's point must be appended, not replace the first flush's")
    }

    /// CQ-2 path (a): a `run.gpsRoute` that already holds real bytes but can no longer be decoded (simulated
    /// corruption) must NOT be silently treated as an empty route and overwritten with just the new points —
    /// that was the original bug's exact failure mode.
    func testFlushRefusesToOverwriteAnUndecodableExistingRoute() {
        let controller = PersistenceController(inMemory: true)
        let run = makeRun(in: controller.container.viewContext)
        let corruptedBytes = Data("not valid gps route json".utf8)
        run.gpsRoute = corruptedBytes
        let buffer = RoutePointBuffer()
        buffer.append(point())

        let result = buffer.flush(into: run)

        XCTAssertEqual(result, .failure(.corruptedExistingRoute))
        XCTAssertEqual(run.gpsRoute, corruptedBytes, "the undecodable bytes must be left exactly as they were")
        XCTAssertEqual(buffer.count, 1, "the pending point must be kept for retry, not silently dropped")
    }

    /// CQ-2 path (b): a merge that fails to encode (e.g. a non-finite Double, which `JSONEncoder`'s default
    /// strategy throws on) must not nil out a route that was already successfully persisted.
    func testFlushRefusesToNilOutAnAlreadyPersistedRouteOnEncodeFailure() {
        let controller = PersistenceController(inMemory: true)
        let run = makeRun(in: controller.container.viewContext)
        let buffer = RoutePointBuffer()

        buffer.append(point())
        XCTAssertEqual(buffer.flush(into: run), .success)
        let persistedAfterFirstFlush = run.gpsRoute
        XCTAssertNotNil(persistedAfterFirstFlush)

        buffer.append(point(lat: .nan))
        let result = buffer.flush(into: run)

        guard case .failure(.encodingFailed) = result else {
            XCTFail("expected an encodingFailed failure, got \(result)")
            return
        }
        XCTAssertEqual(run.gpsRoute, persistedAfterFirstFlush, "must not nil out or truncate the prior route")
        XCTAssertEqual(buffer.count, 1, "the unencodable point must be kept, not silently discarded")
    }
}
