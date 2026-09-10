import CoreData
@testable import Laju
import XCTest

/// T0.6 DoD: a hand-written test `Run` object can be inserted and
/// fetched back correctly via `NSManagedObjectContext`. Requires an iOS
/// Simulator or physical device to execute (XCTest bundles need a host
/// runtime) — written now, execution pending per this round's environment
/// constraints (no simulator runtime installed, no device connected yet).
final class PersistenceTests: XCTestCase {
    func testRunInsertAndFetch() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        let run = Run(context: context)
        run.id = UUID()
        run.startedAt = Date()
        run.distanceMeters = 1234.5
        run.durationSeconds = 600
        run.estimatedPoints = 42
        run.syncStatus = "pendingSync"
        try context.save()

        let request = Run.fetchRequest()
        let results = try context.fetch(request)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.syncStatus, "pendingSync")
        XCTAssertNil(results.first?.serverStatus, "serverStatus must stay distinct from syncStatus")
    }

    func testSyncMetaSingleInstance() {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        let first = controller.syncMeta(in: context)
        let second = controller.syncMeta(in: context)

        XCTAssertEqual(first.objectID, second.objectID, "SyncMeta must be a single-instance entity")
    }
}
