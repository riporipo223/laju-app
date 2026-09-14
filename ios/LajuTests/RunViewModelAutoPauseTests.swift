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
