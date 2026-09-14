import CoreData
import CoreLocation
@testable import Laju
import XCTest

/// T1.4 DoD: the streak bonus in the displayed point estimate must match
/// `PointFormula.calculatePoints` given the actually-computed streak —
/// split out from `RunViewModelTests` to keep that file's body length
/// under SwiftLint's limit.
final class RunViewModelStreakTests: XCTestCase {
    func testStreakBonusFromPriorConsecutiveDaysAppliesToDisplayedEstimate() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()

        // Two prior consecutive days (yesterday, day before) plus today's
        // run about to be started makes a 3-day streak.
        try seedRun(
            estimatedPoints: 5,
            startedAt: XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today)),
            in: context
        )
        try seedRun(
            estimatedPoints: 5,
            startedAt: XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today)),
            in: context
        )

        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)
        viewModel.start()

        // ~220m south — comfortably clears minDistanceKmForPoints (100m),
        // unlike the coincidental "~100m" pattern used elsewhere: the true
        // geodesic distance at this latitude is closer to 99.5m, right on
        // the wrong side of a 100m gate (found via this test's own failure
        // when the exploit fix first landed, 2026-09-13).
        let base = CLLocation(latitude: -7.7057000, longitude: 110.4084000)
        let moved = CLLocation(latitude: -7.7077000, longitude: 110.4084000)
        locationService.locationUpdates.send(base)
        locationService.locationUpdates.send(moved)
        viewModel.stop()

        let summary = try XCTUnwrap(viewModel.completedRunSummary)
        XCTAssertEqual(summary.streakDays, 3)

        let distanceKm = summary.distanceMeters / 1000
        let expectedPoints = PointFormula.calculatePoints(
            distanceKm: distanceKm,
            avgPaceSecPerKm: summary.avgPaceSecPerKm,
            streakDays: 3
        )
        XCTAssertEqual(summary.estimatedPoints, expectedPoints, accuracy: 0.0001)
        XCTAssertGreaterThan(
            summary.estimatedPoints,
            PointFormula.calculatePoints(
                distanceKm: distanceKm,
                avgPaceSecPerKm: summary.avgPaceSecPerKm,
                streakDays: 0
            ),
            "A 3-day streak must award more points than no streak at all"
        )
    }

    func testStreakResetsWhenGapExistsAndTodaysRunQualifies() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()

        // A qualifying run 3 days ago is a MISSED-day gap relative to
        // today (day -1, -2 have no run) — must not extend today's
        // streak past 1, even though today's own run is a real one.
        try seedRun(
            estimatedPoints: 5,
            startedAt: XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: today)),
            in: context
        )

        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)
        viewModel.start()

        // Real movement (~220m, comfortably above the 100m qualifying
        // threshold — see the other test's comment on why "~100m" is too
        // close for comfort) so today's own run counts toward its streak.
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057000, longitude: 110.4084000))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7077000, longitude: 110.4084000))
        viewModel.stop()

        let summary = try XCTUnwrap(viewModel.completedRunSummary)
        XCTAssertEqual(summary.streakDays, 1, "The 3-days-ago run doesn't chain across the gap; only today counts")
        let distanceKm = summary.distanceMeters / 1000
        let expectedPoints = PointFormula.calculatePoints(
            distanceKm: distanceKm,
            avgPaceSecPerKm: summary.avgPaceSecPerKm,
            streakDays: 1
        )
        XCTAssertEqual(summary.estimatedPoints, expectedPoints, accuracy: 0.0001)
    }

    /// Regression test for the exact grinding exploit reported 2026-09-13:
    /// tap Start then Stop immediately (no movement at all) while an
    /// existing multi-day streak is active must earn ZERO points, not a
    /// full streak bonus — confirmed on-device as 6.0/8.0 points from
    /// `distanceMeters=0` runs before this fix (streak_days 3/4).
    func testZeroDistanceRunEarnsNoPointsDespiteExistingStreak() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()

        // 3 consecutive prior qualifying days -> a real streak of 3
        // entering today, exactly the on-device scenario that produced
        // 6.0 points (streak_days=3) before this fix.
        try seedRun(
            estimatedPoints: 5,
            startedAt: XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today)),
            in: context
        )
        try seedRun(
            estimatedPoints: 5,
            startedAt: XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today)),
            in: context
        )
        try seedRun(
            estimatedPoints: 5,
            startedAt: XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: today)),
            in: context
        )

        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        // The exact reported exploit: Start then Stop immediately, no
        // location update sent at all.
        viewModel.start()
        viewModel.stop()

        let summary = try XCTUnwrap(viewModel.completedRunSummary)
        XCTAssertEqual(summary.distanceMeters, 0)
        XCTAssertEqual(
            summary.estimatedPoints,
            0,
            accuracy: 0.0001,
            "A 0-distance run must earn 0 points despite an active 3-day streak — no silent streak bonus"
        )

        // The exploit's other half: today must not itself become a
        // qualifying day that a future run could chain off of.
        let qualifyingDates = PersistenceController.runStartDates(
            in: context,
            minDistanceMeters: PointFormula.minDistanceKmForPoints * 1000
        )
        let startOfToday = calendar.startOfDay(for: today)
        XCTAssertFalse(
            qualifyingDates.contains { calendar.startOfDay(for: $0) == startOfToday },
            "Today's 0-distance run must not count as a qualifying day for tomorrow's streak"
        )
    }

    @discardableResult
    private func seedRun(estimatedPoints: Double, startedAt: Date, in context: NSManagedObjectContext) throws -> Run {
        let run = Run(context: context)
        run.id = UUID()
        run.startedAt = startedAt
        // Qualifying distance (well above PointFormula.minDistanceKmForPoints,
        // 2026-09-13) -- these seeded runs represent genuine prior-day runs,
        // not the grinding exploit this fix closes.
        run.distanceMeters = 500
        run.durationSeconds = 0
        run.estimatedPoints = estimatedPoints
        run.syncStatus = "pendingSync"
        try context.save()
        return run
    }
}
