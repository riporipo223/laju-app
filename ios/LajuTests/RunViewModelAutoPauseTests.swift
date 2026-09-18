import CoreData
import CoreLocation
@testable import Laju
import XCTest

/// T1.11 DoD: sustained no-movement auto-pauses without user input, distinct from manual pause, resumes like
/// manual pause, and excludes auto-paused time from duration. Uses a short injected `autoPauseThresholdSeconds`
/// so this exercises the REAL watchdog timer without waiting the real 60s default.
final class RunViewModelAutoPauseTests: XCTestCase {
    private func makeViewModel(context: NSManagedObjectContext) -> (RunViewModel, LocationTrackingService) {
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context, autoPauseThresholdSeconds: 0.5)
        return (viewModel, locationService)
    }

    func testSustainedNoMovementPastThresholdAutoPausesWithoutUserInput() {
        let controller = PersistenceController(inMemory: true)
        let (viewModel, locationService) = makeViewModel(context: controller.container.viewContext)

        viewModel.start()
        // Establishes the anchor — the watchdog has nothing to measure from until one exists.
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        XCTAssertFalse(viewModel.isPaused)

        let autoPaused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in viewModel.isPaused }, object: nil)
        wait(for: [autoPaused], timeout: 3)

        XCTAssertTrue(viewModel.isAutoPaused, "Must be marked as an AUTO pause, not manual")
    }

    func testResumeAfterAutoPauseBehavesLikeResumeAfterManualPause() {
        let controller = PersistenceController(inMemory: true)
        let (viewModel, locationService) = makeViewModel(context: controller.container.viewContext)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        let autoPaused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in viewModel.isPaused }, object: nil)
        wait(for: [autoPaused], timeout: 3)

        viewModel.resume()

        XCTAssertFalse(viewModel.isPaused)
        XCTAssertFalse(viewModel.isAutoPaused)
        XCTAssertTrue(viewModel.isRunning, "Resume from auto-pause must leave the run active, same as manual")
    }

    /// Regression test for the 2026-09-15 false-trigger report: a user genuinely walking under degraded GPS
    /// (locked screen / urban canyon near Sari Harjo) got auto-paused with "kamu berhenti bergerak" even
    /// though they never stopped. Root cause: fixes with accuracy between `RunViewModel
    /// .anchorAccuracyThresholdMeters` (10m) and `LocationTrackingService`'s own accept ceiling (20m) pass
    /// the service's filter (so they DO arrive) but fail the stricter anchor-confirm threshold — the watchdog
    /// previously had no signal for "fixes are arriving but too noisy to trust," so it read that exactly like
    /// silence. This exercises the "beyond the anchor's stationary radius, but too poor to trust" branch
    /// specifically — each fix is a different, walking-speed-plausible coordinate at accuracy=15m (passes
    /// `LocationTrackingService`'s 20m ceiling, fails the 10m anchor threshold).
    func testSustainedPoorAccuracyFixesBeyondAnchorRadiusDoNotTriggerAutoPause() {
        let controller = PersistenceController(inMemory: true)
        let (viewModel, locationService) = makeViewModel(context: controller.container.viewContext)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        XCTAssertFalse(viewModel.isPaused)

        let degradedFixes: [(Double, Double)] = [
            (-7.70620, 110.40850),
            (-7.70640, 110.40860),
            (-7.70660, 110.40870),
            (-7.70680, 110.40880)
        ]
        for (lat, lng) in degradedFixes {
            locationService.locationUpdates.send(
                CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    altitude: 0,
                    horizontalAccuracy: 15,
                    verticalAccuracy: 0,
                    timestamp: Date()
                )
            )
            Thread.sleep(forTimeInterval: 0.3) // spans past the 0.5s injected threshold across the sequence
        }

        XCTAssertFalse(
            viewModel.isPaused,
            "Degraded-accuracy fixes that are still arriving must not read as silence — the user never stopped"
        )
    }

    /// Same false-trigger family, the "within the anchor's stationary radius, but accuracy too poor to trust
    /// as genuinely-stationary evidence" branch — geometrically close to the anchor (so it can't confirm
    /// movement either way), but a degraded fix here must not silently count toward the pause clock the way a
    /// GOOD-accuracy stationary fix correctly does (see
    /// `testSustainedNoMovementPastThresholdAutoPausesWithoutUserInput`,
    /// the deliberate counterpart to this test — that one must still trigger, unchanged).
    func testSustainedPoorAccuracyFixesWithinAnchorRadiusDoNotTriggerAutoPause() {
        let controller = PersistenceController(inMemory: true)
        let (viewModel, locationService) = makeViewModel(context: controller.container.viewContext)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        XCTAssertFalse(viewModel.isPaused)

        for _ in 0 ..< 4 {
            locationService.locationUpdates.send(
                CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: -7.70571, longitude: 110.40841),
                    altitude: 0,
                    horizontalAccuracy: 15,
                    verticalAccuracy: 0,
                    timestamp: Date()
                )
            )
            Thread.sleep(forTimeInterval: 0.3)
        }

        XCTAssertFalse(
            viewModel.isPaused,
            "A degraded fix close to the anchor is ambiguous, not confirmed-stationary — must not auto-pause"
        )
    }

    func testAutoPausedTimeIsExcludedFromDuration() {
        let controller = PersistenceController(inMemory: true)
        let (viewModel, locationService) = makeViewModel(context: controller.container.viewContext)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        let autoPaused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in viewModel.isPaused }, object: nil)
        wait(for: [autoPaused], timeout: 3)

        let durationAtPause = viewModel.liveActiveDuration()
        let stayedPaused = expectation(description: "stayed paused a bit longer")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { stayedPaused.fulfill() }
        wait(for: [stayedPaused], timeout: 1)

        XCTAssertEqual(
            viewModel.liveActiveDuration(), durationAtPause, accuracy: 0.05,
            "Duration must not advance while auto-paused, exactly like manual pause"
        )
    }
}
