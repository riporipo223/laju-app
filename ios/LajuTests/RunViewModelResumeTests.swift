import CoreData
import CoreLocation
@testable import Laju
import XCTest

/// T1.14 DoD: "Resume continues tracking from the previously-saved
/// distance/duration/gpsRoute state, not from zero." — split from
/// `RunViewModelTests` to keep that file's body length under SwiftLint's
/// limit.
final class RunViewModelResumeTests: XCTestCase {
    func testResumeRecoveredRunSeedsDistanceDurationAndRouteInsteadOfStartingFromZero() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let run = try seedUnfinishedRun(distanceMeters: 750, durationSeconds: 180, in: context)

        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)
        viewModel.resumeRecoveredRun(run)

        XCTAssertTrue(viewModel.isRunning)
        XCTAssertEqual(viewModel.distanceMeters, 750, "Must seed from the persisted distance, not reset to 0")
        XCTAssertEqual(viewModel.pointCount, 1, "Must seed pointCount from the persisted route")
        XCTAssertGreaterThanOrEqual(
            viewModel.liveActiveDuration(), 180,
            "Must seed accumulatedActiveDuration from the persisted value, not restart the clock"
        )
    }

    /// The DoD's own emphasis: duration persistence must work for a
    /// crash mid-active-segment (never paused), not only a
    /// crash-after-pause case where `durationSeconds` happens to already
    /// be saved from `pause()`'s own explicit write.
    func testResumeSeedsDurationEvenWhenTheOriginalRunWasNeverPaused() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        // durationSeconds=45 here simulates what T1.14's periodicFlush()
        // fix persisted mid-segment — pause() was never called.
        let run = try seedUnfinishedRun(distanceMeters: 200, durationSeconds: 45, in: context)

        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)
        viewModel.resumeRecoveredRun(run)

        XCTAssertGreaterThanOrEqual(viewModel.liveActiveDuration(), 45)
    }

    func testMovementAfterResumeAddsOnTopOfTheSeededDistanceNotFromZero() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let run = try seedUnfinishedRun(distanceMeters: 1000, durationSeconds: 200, in: context)

        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)
        viewModel.resumeRecoveredRun(run)

        // Injected directly into the publisher RunViewModel subscribes to
        // (same pattern as RunViewModelTests) — bypasses
        // LocationTrackingService's own filtering, which is already
        // covered elsewhere; this test is only about RunViewModel's OWN
        // post-resume accumulation.
        let base = CLLocation(latitude: -7.7057000, longitude: 110.4084000)
        let moved = CLLocation(latitude: -7.7077000, longitude: 110.4084000) // ~220m
        locationService.locationUpdates.send(base)
        locationService.locationUpdates.send(moved)

        XCTAssertGreaterThan(viewModel.distanceMeters, 1000, "New movement must ADD to the seeded 1000m")
    }

    @discardableResult
    private func seedUnfinishedRun(
        distanceMeters: Double,
        durationSeconds: Double,
        in context: NSManagedObjectContext
    ) throws -> Run {
        let run = Run(context: context)
        run.id = UUID()
        run.startedAt = Date().addingTimeInterval(-durationSeconds)
        run.distanceMeters = distanceMeters
        run.durationSeconds = durationSeconds
        run.estimatedPoints = 0
        run.syncStatus = "pendingSync"
        let point = GPSPoint(lat: -7.7057, lng: 110.4084, timestamp: Date(), elevation: 0)
        run.gpsRoute = try JSONEncoder().encode([point])
        try context.save()
        return run
    }
}
