@testable import Laju
import XCTest

/// T1.4 DoD: streak count must reset correctly when a day is missed,
/// verified with manually seeded run timestamps — no Core Data needed
/// here, `StreakTracker.currentStreakDays` is a pure function.
final class StreakTrackerTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func daysAgo(_ dayCount: Int, from reference: Date) throws -> Date {
        try XCTUnwrap(calendar.date(byAdding: .day, value: -dayCount, to: reference))
    }

    func testNoPriorRunsGivesStreakOfOne() {
        let today = Date()
        // `runDates` includes today's own (just-created) run — see
        // RunViewModel.start()'s doc comment on why this is always true
        // in practice — so a lone run gives a streak of 1, not 0.
        let streak = StreakTracker.currentStreakDays(asOf: today, runDates: [today])
        XCTAssertEqual(streak, 1)
    }

    func testConsecutiveDaysCountCorrectly() throws {
        let today = Date()
        let runDates = try (0 ..< 4).map { try daysAgo($0, from: today) } // today, -1, -2, -3
        XCTAssertEqual(StreakTracker.currentStreakDays(asOf: today, runDates: runDates), 4)
    }

    func testStreakResetsAtFirstMissedDay() throws {
        let today = Date()
        // today, -1, -2 present; -3 MISSING; -4, -5 present but past the
        // gap and must not be counted.
        let runDates = try [0, 1, 2, 4, 5].map { try daysAgo($0, from: today) }
        XCTAssertEqual(StreakTracker.currentStreakDays(asOf: today, runDates: runDates), 3)
    }

    func testMultipleRunsSameDayCountOnceNotPerRun() {
        let today = Date()
        let runDates = [today, today.addingTimeInterval(60), today.addingTimeInterval(120)]
        XCTAssertEqual(StreakTracker.currentStreakDays(asOf: today, runDates: runDates), 1)
    }

    func testNoRunTodayBreaksStreakImmediately() throws {
        let today = Date()
        // Only prior-day runs, none today — streak counted "as of today"
        // must be 0 since today itself has no run.
        let runDates = try [1, 2, 3].map { try daysAgo($0, from: today) }
        XCTAssertEqual(StreakTracker.currentStreakDays(asOf: today, runDates: runDates), 0)
    }

    // MARK: - hasRun (T1.4 DoD item 3, Round 7 finding N7-P12)

    func testHasRunIsTrueWhenTodayHasAQualifyingRun() {
        let today = Date()
        XCTAssertTrue(StreakTracker.hasRun(on: today, runDates: [today]))
    }

    func testHasRunIsFalseWhenTodayHasNoRun() throws {
        let today = Date()
        let runDates = try [1, 2].map { try daysAgo($0, from: today) }
        XCTAssertFalse(StreakTracker.hasRun(on: today, runDates: runDates))
    }

    func testHasRunIgnoresTimeOfDayOnlyComparingCalendarDay() {
        let today = Date()
        let earlierToday = calendar.startOfDay(for: today)
        XCTAssertTrue(StreakTracker.hasRun(on: today, runDates: [earlierToday]))
    }
}
