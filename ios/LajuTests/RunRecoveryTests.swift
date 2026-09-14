import CoreData
@testable import Laju
import XCTest

/// T1.14 DoD: an unfinished run (no `endedAt`) is detected at launch and
/// surfaced with the data the recovery prompt needs; "Save as finished"
/// closes it at its last persisted state, not "now".
final class RunRecoveryTests: XCTestCase {
    func testResolveOnLaunchReturnsTheUnfinishedRunWithItsPersistedData() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let seeded = try seedUnfinishedRun(startedAt: Date(), distanceMeters: 812, durationSeconds: 240, in: context)

        let offered = RunRecovery.resolveOnLaunch(in: context)

        XCTAssertEqual(offered?.id, seeded.id)
        XCTAssertEqual(offered?.distanceMeters, 812)
        XCTAssertNil(offered?.endedAt, "Not finalized yet — this is the one the user still has to decide about")
    }

    /// Spec: "cuma run TERAKHIR yang ditawarkan resume, run-run
    /// sebelumnya otomatis di-'Save as finished'" — force-kills can
    /// happen more than once before ever being resolved.
    func testOlderUnfinishedRunsAreAutoFinalizedLeavingOnlyTheMostRecentToPromptFor() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let older = try seedUnfinishedRun(
            startedAt: Date().addingTimeInterval(-600),
            distanceMeters: 100,
            durationSeconds: 60,
            in: context
        )
        let mostRecent = try seedUnfinishedRun(
            startedAt: Date().addingTimeInterval(-60),
            distanceMeters: 50,
            durationSeconds: 30,
            in: context
        )

        let offered = RunRecovery.resolveOnLaunch(in: context)

        XCTAssertEqual(offered?.id, mostRecent.id)
        XCTAssertNotNil(older.endedAt, "Superseded by a later session — should be auto-finalized, not left dangling")
    }

    /// Spec: staleness cutoff — a run abandoned long ago shouldn't be
    /// offered Resume (stale GPS context). 25 hours comfortably clears
    /// `RunRecovery.staleAfter` (24h).
    func testAStaleUnfinishedRunIsAutoFinalizedInsteadOfOfferedForResume() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let stale = try seedUnfinishedRun(
            startedAt: Date().addingTimeInterval(-25 * 3600),
            distanceMeters: 300,
            durationSeconds: 200,
            in: context
        )

        let offered = RunRecovery.resolveOnLaunch(in: context)

        XCTAssertNil(offered, "Too stale to resume — nothing left needing a user decision")
        XCTAssertNotNil(stale.endedAt, "Auto-finalized instead")
    }

    func testResolveOnLaunchReturnsNilWhenNothingIsUnfinished() {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        XCTAssertNil(RunRecovery.resolveOnLaunch(in: context))
    }

    /// "endedAt ke timestamp fix GPS terakhir yang ada, bukan waktu app
    /// dibuka lagi" — the dead-app gap must not count as run time.
    func testFinalizeSetsEndedAtToTheLastGPSPointTimestampNotNow() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let lastFixTime = Date().addingTimeInterval(-500) // long before "now"
        let run = try seedUnfinishedRun(
            startedAt: Date().addingTimeInterval(-600),
            distanceMeters: 400,
            durationSeconds: 90,
            lastGPSPointTimestamp: lastFixTime,
            in: context
        )

        RunRecovery.finalize(run, in: context)

        XCTAssertEqual(run.endedAt?.timeIntervalSince1970 ?? 0, lastFixTime.timeIntervalSince1970, accuracy: 0.001)
    }

    func testFinalizeFallsBackToStartedAtWhenNoGPSPointWasEverFlushed() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let startedAt = Date().addingTimeInterval(-30)
        let run = try seedUnfinishedRun(startedAt: startedAt, distanceMeters: 0, durationSeconds: 0, in: context)

        RunRecovery.finalize(run, in: context)

        XCTAssertEqual(run.endedAt?.timeIntervalSince1970 ?? 0, startedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testFinalizeComputesEstimatedPointsMatchingPointFormulaForThePersistedDistanceAndDuration() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let run = try seedUnfinishedRun(startedAt: Date(), distanceMeters: 1000, durationSeconds: 300, in: context)

        let summary = RunRecovery.finalize(run, in: context)

        let expected = PointFormula.calculatePoints(distanceKm: 1.0, avgPaceSecPerKm: 300, streakDays: 1)
        XCTAssertEqual(summary.estimatedPoints, expected, accuracy: 0.0001)
        XCTAssertEqual(run.estimatedPoints, expected, accuracy: 0.0001)
    }

    @discardableResult
    private func seedUnfinishedRun(
        startedAt: Date,
        distanceMeters: Double,
        durationSeconds: Double,
        lastGPSPointTimestamp: Date? = nil,
        in context: NSManagedObjectContext
    ) throws -> Run {
        let run = Run(context: context)
        run.id = UUID()
        run.startedAt = startedAt
        run.distanceMeters = distanceMeters
        run.durationSeconds = durationSeconds
        run.estimatedPoints = 0
        run.syncStatus = "pendingSync"
        // endedAt deliberately left nil — this is what makes it "unfinished".
        if let lastGPSPointTimestamp {
            let point = GPSPoint(lat: -7.7057, lng: 110.4084, timestamp: lastGPSPointTimestamp, elevation: 0)
            run.gpsRoute = try JSONEncoder().encode([point])
        }
        try context.save()
        return run
    }
}
