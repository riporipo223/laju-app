import CoreData
import CoreLocation
@testable import Laju
import XCTest

/// Regression test for the T0.6/B6-3 incremental-flush mechanism
/// (`RunViewModel.periodicFlush()`) — 2026-09-13, a device force-kill
/// report claimed this had regressed. Diagnosis found the timer itself
/// intact (untouched by the pause/resume/SplitTracker refactors this
/// phase); the reported runs were simply killed before their first 30s
/// flush window elapsed — a real but pre-existing design edge (class
/// doc: "30s caps worst-case loss to half a minute"), not a regression.
/// No test previously exercised the TIMER trigger at all, only the
/// count-threshold one indirectly — this closes that gap so a real
/// future regression here fails a test instead of only surfacing on the
/// next manual device test.
final class RunViewModelPersistenceTests: XCTestCase {
    func testPeriodicFlushPersistsAPendingPointBeforeTheCountThresholdIsReached() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        // Short interval so this exercises the REAL Combine
        // `Timer.publish` path without a 30s wait.
        let viewModel = RunViewModel(
            locationService: locationService,
            context: context,
            flushIntervalSeconds: 0.2
        )

        viewModel.start()
        // One point only — nowhere near saveEveryNPoints (20), so the
        // timer is the ONLY thing that can flush it.
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))

        let run = try XCTUnwrap(try context.fetch(Run.fetchRequest()).first)
        XCTAssertNil(run.gpsRoute, "Should not be flushed yet — the timer hasn't fired")

        // Polls the real condition rather than sleeping a fixed duration —
        // a fixed `asyncAfter` occasionally missed its own margin under
        // parallel-test CPU load (flaky), even though the timer itself
        // fired correctly; polling only fails if the flush genuinely
        // never happens, not from scheduler jitter.
        let flushed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in run.gpsRoute != nil },
            object: nil
        )
        wait(for: [flushed], timeout: 3)

        let route = GPSPoint.decodeRoute(from: run.gpsRoute)
        XCTAssertEqual(route.count, 1, "The periodic timer must flush pendingPoints to gpsRoute on its own")
    }

    /// The class doc's own stated guarantee — a run killed before its
    /// first flush trigger (count OR timer) has nothing to recover
    /// beyond the `Run` row itself (B6-3). This is what actually
    /// happened in the on-device report (both test runs' lifetimes were
    /// shorter than the 30s interval) — documented here as a passing
    /// test, not a bug, so it isn't re-investigated as one again.
    func testARunKilledBeforeTheFirstFlushTriggerHasNoGpsRouteButKeepsItsRow() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(
            locationService: locationService,
            context: context,
            flushIntervalSeconds: 30
        )

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        // No stop(), no wait — simulates a force-kill within the first
        // fraction of a second, well before either flush trigger.

        let run = try XCTUnwrap(try context.fetch(Run.fetchRequest()).first, "B6-3: the Run row itself must survive")
        XCTAssertNil(run.gpsRoute, "Nothing flushed yet is the expected state, not a bug")
    }

    /// T1.14 (product-spec §4.14) DoD: `durationSeconds` must be
    /// persisted incrementally, not just at `pause()`/`stop()` — a crash
    /// mid-active-segment that never paused previously left it at 0
    /// forever (Round 7 B7-2/B7-P1). No new location points arrive here
    /// at all, so `run.durationSeconds` only advances if the TIMER
    /// itself sets it directly (`periodicFlush()`), not indirectly via
    /// a point-triggered flush.
    func testPeriodicFlushPersistsDurationSecondsEvenWithNoNewPointsAtAll() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context, flushIntervalSeconds: 0.2)

        viewModel.start()
        let run = try XCTUnwrap(try context.fetch(Run.fetchRequest()).first)
        XCTAssertEqual(run.durationSeconds, 0)

        let durationPersisted = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in run.durationSeconds > 0 },
            object: nil
        )
        wait(for: [durationPersisted], timeout: 3)
    }
}
