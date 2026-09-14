import CoreData
import CoreLocation
@testable import Laju
import XCTest

/// T1.2 DoD: `estimatedPoints` set on Stop must match `PointFormula`'s
/// output for the recorded distance/pace, and be persisted to the `Run`
/// entity — verified directly against `RunViewModel`, not through UI
/// interaction (no simulator/device access this pass — see task summary).
final class RunViewModelTests: XCTestCase {
    func testStopWithNoMovementProducesZeroPointSummary() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()
        viewModel.stop()

        let summary = try XCTUnwrap(
            viewModel.completedRunSummary,
            "completedRunSummary must be set synchronously by stop() (product-spec AC 4.3.1)"
        )
        XCTAssertEqual(summary.distanceMeters, 0)
        // streakDays is 1, not 0 (T1.4): this run is the only one in an
        // empty context, so it's its own 1-day streak — see
        // RunViewModel.start()'s doc comment.
        XCTAssertEqual(
            summary.estimatedPoints,
            PointFormula.calculatePoints(distanceKm: 0, avgPaceSecPerKm: 0, streakDays: 1),
            accuracy: 0.0001
        )

        let run = try XCTUnwrap(try context.fetch(Run.fetchRequest()).first)
        XCTAssertEqual(run.estimatedPoints, summary.estimatedPoints, accuracy: 0.0001)
    }

    func testStopWithMovementComputesMatchingPoints() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()

        // Injected directly into the publisher RunViewModel subscribes to
        // — bypasses LocationTrackingService's own accuracy/speed/jitter
        // filtering (already covered by T0.9's tests), isolating this
        // test to T1.2's own point-formula wiring.
        let base = CLLocation(latitude: -7.7057000, longitude: 110.4084000)
        let moved = CLLocation(latitude: -7.7066000, longitude: 110.4084000) // ~100m south
        locationService.locationUpdates.send(base)
        locationService.locationUpdates.send(moved)

        viewModel.stop()

        let summary = try XCTUnwrap(viewModel.completedRunSummary)
        XCTAssertGreaterThan(summary.distanceMeters, 0, "Simulated movement should produce non-zero distance")

        let distanceKm = summary.distanceMeters / 1000
        let expectedPace = distanceKm > 0 ? summary.durationSeconds / distanceKm : 0
        XCTAssertEqual(summary.avgPaceSecPerKm, expectedPace, accuracy: 0.0001)

        // streakDays is 1, not 0 (T1.4) — same reasoning as
        // testStopWithNoMovementProducesZeroPointSummary above.
        let expectedPoints = PointFormula.calculatePoints(
            distanceKm: distanceKm,
            avgPaceSecPerKm: summary.avgPaceSecPerKm,
            streakDays: 1
        )
        XCTAssertEqual(summary.estimatedPoints, expectedPoints, accuracy: 0.0001)

        let run = try XCTUnwrap(try context.fetch(Run.fetchRequest()).first)
        XCTAssertEqual(run.estimatedPoints, summary.estimatedPoints, accuracy: 0.0001)
    }

    // MARK: - T1.2b: pause/resume

    func testPauseExcludesElapsedTimeFromDuration() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()
        Thread.sleep(forTimeInterval: 0.3) // active segment 1
        viewModel.pause()
        Thread.sleep(forTimeInterval: 0.5) // paused gap — must NOT be counted
        viewModel.resume()
        Thread.sleep(forTimeInterval: 0.3) // active segment 2
        viewModel.stop()

        let summary = try XCTUnwrap(viewModel.completedRunSummary)
        // Active time is ~0.6s; wall-clock span is ~1.1s. Generous
        // tolerance for test-runner scheduling jitter, but tight enough
        // that counting the paused gap would clearly fail this.
        XCTAssertEqual(summary.durationSeconds, 0.6, accuracy: 0.25)
        XCTAssertLessThan(summary.durationSeconds, 0.9, "Paused interval must not be counted toward duration")
    }

    func testNoPointsRecordedWhilePaused() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057000, longitude: 110.4084000))
        viewModel.pause()

        // These must be ignored by handle()'s own guard, not merely
        // absent because CLLocationManager was told to stop — a real
        // device could still have one in flight when pause() is called.
        locationService.locationUpdates.send(CLLocation(latitude: -7.7066000, longitude: 110.4084000))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7075000, longitude: 110.4084000))
        XCTAssertEqual(viewModel.pointCount, 1, "No points should be accepted while paused")

        viewModel.resume()
        viewModel.stop()

        let run = try XCTUnwrap(try context.fetch(Run.fetchRequest()).first)
        let routeData = try XCTUnwrap(run.gpsRoute)
        let points = try JSONDecoder().decode([GPSPoint].self, from: routeData)
        XCTAssertEqual(points.count, 1, "gpsRoute must not gain points recorded during the paused interval")
    }

    func testCurrentEstimatedPointsFreezesWhilePausedThenResumesUpdating() {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057000, longitude: 110.4084000))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7066000, longitude: 110.4084000))
        let pointsBeforePause = viewModel.currentEstimatedPoints

        viewModel.pause()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7075000, longitude: 110.4084000))
        XCTAssertEqual(
            viewModel.currentEstimatedPoints,
            pointsBeforePause,
            accuracy: 0.0001,
            "currentEstimatedPoints must not change while paused"
        )

        viewModel.resume()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7084000, longitude: 110.4084000))
        XCTAssertNotEqual(
            viewModel.currentEstimatedPoints,
            pointsBeforePause,
            "currentEstimatedPoints must resume updating after resume"
        )

        viewModel.stop()
    }

    // MARK: - Bugfix (2026-09-12): poor-accuracy first fix seeding a false anchor

    func testPoorAccuracyFirstFixDoesNotSeedFalseAnchorDrift() {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()

        // Reproduces the on-device incident found 2026-09-12 (device
        // stationary indoors): a still-settling first fix
        // (horizontalAccuracy=15.11m) followed 12s later by a
        // much-better fix (horizontalAccuracy=3.20m) landing ~35m away
        // — coordinates taken directly from that run's console log.
        let poorFirstFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -7.756_026_521_024_273, longitude: 110.382_714_520_525_52),
            altitude: 159.9,
            horizontalAccuracy: 15.11,
            verticalAccuracy: 5,
            timestamp: Date()
        )
        let goodSecondFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -7.756_316_267_037_607, longitude: 110.382_837_589_905_88),
            altitude: 159.16,
            horizontalAccuracy: 3.20,
            verticalAccuracy: 5,
            timestamp: Date().addingTimeInterval(12)
        )
        locationService.locationUpdates.send(poorFirstFix)
        locationService.locationUpdates.send(goodSecondFix)

        XCTAssertEqual(
            viewModel.distanceMeters,
            0,
            accuracy: 0.0001,
            "A poor-accuracy first fix must not seed the anchor, so an accurate later fix isn't read as movement"
        )

        // A third, accurate fix genuinely far from the now-established
        // anchor (goodSecondFix) must still count as real movement.
        let realMovement = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -7.757_300_0, longitude: 110.382_800_0),
            altitude: 159,
            horizontalAccuracy: 4,
            verticalAccuracy: 5,
            timestamp: Date().addingTimeInterval(20)
        )
        locationService.locationUpdates.send(realMovement)
        XCTAssertGreaterThan(viewModel.distanceMeters, 0, "Genuine movement with an accurate fix must still be counted")

        viewModel.stop()
    }

    // MARK: - T1.3: level-up detection

    func testStopDetectsLevelUp() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        // Seed prior cumulative points just below level 2's threshold
        // (100, database-api-spec.md §1).
        try seedRun(estimatedPoints: 95, in: context)

        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)
        viewModel.start()

        // ~11km (0.1° latitude) — comfortably enough distance that even
        // at the 0.5x "too fast" pace multiplier (near-zero test
        // duration lands well under the 3:00/km bracket), this run's
        // points alone push the 95-point prior total past 100.
        let base = CLLocation(latitude: -7.7057000, longitude: 110.4084000)
        let moved = CLLocation(latitude: -7.6057000, longitude: 110.4084000)
        locationService.locationUpdates.send(base)
        locationService.locationUpdates.send(moved)
        viewModel.stop()

        let summary = try XCTUnwrap(viewModel.completedRunSummary)
        let leveledUpTo = try XCTUnwrap(summary.leveledUpTo, "Crossing the level-2 threshold should report a level-up")
        XCTAssertEqual(leveledUpTo.level, 2)
        XCTAssertEqual(leveledUpTo.title, "Rajin")
    }

    func testStopDoesNotReportLevelUpWhenStillBelowThreshold() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        // Well below level 2's threshold (100), and this run's own
        // ~100m movement contributes only a small fraction of a point —
        // nowhere near enough to cross it.
        try seedRun(estimatedPoints: 10, in: context)

        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)
        viewModel.start()

        let base = CLLocation(latitude: -7.7057000, longitude: 110.4084000)
        let moved = CLLocation(latitude: -7.7066000, longitude: 110.4084000)
        locationService.locationUpdates.send(base)
        locationService.locationUpdates.send(moved)
        viewModel.stop()

        let summary = try XCTUnwrap(viewModel.completedRunSummary)
        XCTAssertNil(summary.leveledUpTo)
    }

    @discardableResult
    private func seedRun(estimatedPoints: Double, in context: NSManagedObjectContext) throws -> Run {
        try seedRun(estimatedPoints: estimatedPoints, startedAt: Date(), in: context)
    }

    @discardableResult
    private func seedRun(estimatedPoints: Double, startedAt: Date, in context: NSManagedObjectContext) throws -> Run {
        let run = Run(context: context)
        run.id = UUID()
        run.startedAt = startedAt
        run.distanceMeters = 0
        run.durationSeconds = 0
        run.estimatedPoints = estimatedPoints
        run.syncStatus = "pendingSync"
        try context.save()
        return run
    }
}
