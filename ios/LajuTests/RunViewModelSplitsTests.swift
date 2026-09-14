import CoreLocation
@testable import Laju
import XCTest

/// T1.10 DoD: per-km splits (`RunSplit`) must partition `distanceMeters`
/// exactly, mark the trailing partial split, and exclude paused time from
/// a split's duration even when the pause falls inside that split's own
/// distance range — split out from `RunViewModelTests` to keep that file
/// under SwiftLint's type-body-length limit.
final class RunViewModelSplitsTests: XCTestCase {
    func testSplitDistancesSumExactlyToTotalDistance() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()
        // ~0.01° steps (~1.1km each at this latitude) — comfortably clears
        // 1000m per step, so each addition closes its own split.
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7157, longitude: 110.4084))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7257, longitude: 110.4084))
        // Trailing partial: a small step that doesn't reach another 1000m.
        locationService.locationUpdates.send(CLLocation(latitude: -7.7277, longitude: 110.4084))
        viewModel.stop()

        let summary = try XCTUnwrap(viewModel.completedRunSummary)
        let summedSplitDistance = summary.splits.reduce(0) { $0 + $1.distanceMeters }
        XCTAssertEqual(summedSplitDistance, summary.distanceMeters, accuracy: 0.01)
    }

    func testTrailingSplitIsMarkedPartial() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7157, longitude: 110.4084)) // completes split 1
        locationService.locationUpdates.send(CLLocation(latitude: -7.7177, longitude: 110.4084)) // partial ~220m
        viewModel.stop()

        let summary = try XCTUnwrap(viewModel.completedRunSummary)
        XCTAssertEqual(summary.splits.count, 2)
        XCTAssertFalse(summary.splits[0].isPartial)
        XCTAssertTrue(summary.splits[1].isPartial)
    }

    func testNoSplitsWhenDistanceNeverReaches1km() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057000, longitude: 110.4084000))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7077000, longitude: 110.4084000)) // ~220m
        viewModel.stop()

        let summary = try XCTUnwrap(viewModel.completedRunSummary)
        XCTAssertEqual(summary.splits.count, 1)
        XCTAssertTrue(summary.splits[0].isPartial)
        XCTAssertEqual(summary.splits[0].distanceMeters, summary.distanceMeters, accuracy: 0.01)
    }

    /// The exact DoD scenario: a pause occurs mid-split (before the
    /// boundary that eventually closes it) — the split's own duration
    /// must reflect only active time, not the paused gap.
    func testSplitSpanningAPauseExcludesThePausedTimeFromItsDuration() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()
        // ~200m — real movement, but nowhere near the 1000m boundary yet.
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7075, longitude: 110.4084))

        viewModel.pause()
        Thread.sleep(forTimeInterval: 0.3) // the paused gap — must NOT count
        viewModel.resume()

        // Crosses the 1000m boundary within the SAME split (no boundary
        // was crossed before the pause).
        locationService.locationUpdates.send(CLLocation(latitude: -7.7177, longitude: 110.4084))
        viewModel.stop()

        let summary = try XCTUnwrap(viewModel.completedRunSummary)
        XCTAssertEqual(summary.splits.count, 1)
        XCTAssertLessThan(
            summary.splits[0].durationSeconds,
            0.3,
            "The split's duration must reflect only active time — the 0.3s pause must not be counted"
        )
    }
}
