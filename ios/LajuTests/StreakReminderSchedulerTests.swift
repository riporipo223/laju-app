import Foundation
@testable import Laju
import UserNotifications
import XCTest

private final class NotificationSchedulingSpy: NotificationScheduling {
    private(set) var requestAuthorizationCallCount = 0
    var authorizationResult = true
    var authorizationStatusToReturn: UNAuthorizationStatus = .notDetermined
    private(set) var removeAllPendingCallCount = 0
    private(set) var scheduledIdentifiers: [String] = []
    private(set) var scheduledDateComponents: [String: DateComponents] = [:]

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        requestAuthorizationCallCount += 1
        completion(authorizationResult)
    }

    func getAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        completion(authorizationStatusToReturn)
    }

    func removeAllPending() {
        removeAllPendingCallCount += 1
        scheduledIdentifiers.removeAll()
        scheduledDateComponents.removeAll()
    }

    func schedule(identifier: String, dateComponents: DateComponents, title _: String, body _: String) {
        scheduledIdentifiers.append(identifier)
        scheduledDateComponents[identifier] = dateComponents
    }
}

/// T1.16 DoD: reminders schedule N days ahead (not one reschedule-on-open notification), skip entirely with
/// no active streak, never stack duplicates on repeated reschedule calls, and — found in 2026-09-14 review —
/// a plain app foreground before today's run must not silently wipe today's own already-scheduled reminder.
final class StreakReminderSchedulerTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testZeroStreakSchedulesNothing() {
        let spy = NotificationSchedulingSpy()
        let scheduler = StreakReminderScheduler(notifications: spy, calendar: calendar)

        scheduler.reschedule(currentStreakDays: 0, hasRunToday: false)

        XCTAssertTrue(spy.scheduledIdentifiers.isEmpty)
    }

    func testActiveStreakWithRunTodayExcludesTodayFromTheWindow() {
        let spy = NotificationSchedulingSpy()
        let scheduler = StreakReminderScheduler(notifications: spy, calendar: calendar)
        let now = Date()

        scheduler.reschedule(currentStreakDays: 3, hasRunToday: true, from: now)

        XCTAssertEqual(spy.scheduledIdentifiers.count, StreakReminderScheduler.daysAhead)
        let todayIdentifier = StreakReminderScheduler.identifier(for: now, calendar: calendar)
        XCTAssertFalse(spy.scheduledIdentifiers.contains(todayIdentifier))
    }

    func testActiveStreakWithoutRunTodayIncludesTodayInTheWindow() {
        let spy = NotificationSchedulingSpy()
        let scheduler = StreakReminderScheduler(notifications: spy, calendar: calendar)
        let now = Date()

        scheduler.reschedule(currentStreakDays: 3, hasRunToday: false, from: now)

        XCTAssertEqual(spy.scheduledIdentifiers.count, StreakReminderScheduler.daysAhead + 1)
        let todayIdentifier = StreakReminderScheduler.identifier(for: now, calendar: calendar)
        XCTAssertTrue(spy.scheduledIdentifiers.contains(todayIdentifier))
    }

    func testReschedulingDoesNotStackDuplicates() {
        let spy = NotificationSchedulingSpy()
        let scheduler = StreakReminderScheduler(notifications: spy, calendar: calendar)

        scheduler.reschedule(currentStreakDays: 3, hasRunToday: true)
        scheduler.reschedule(currentStreakDays: 3, hasRunToday: true)

        XCTAssertEqual(spy.removeAllPendingCallCount, 2)
        XCTAssertEqual(spy.scheduledIdentifiers.count, StreakReminderScheduler.daysAhead)
    }

    func testScheduledTimeUsesTheConfiguredReminderHour() {
        let spy = NotificationSchedulingSpy()
        let scheduler = StreakReminderScheduler(notifications: spy, calendar: calendar)

        scheduler.reschedule(currentStreakDays: 1, hasRunToday: false)

        for components in spy.scheduledDateComponents.values {
            XCTAssertEqual(components.hour, StreakReminderScheduler.reminderHour)
            XCTAssertEqual(components.minute, 0)
        }
    }

    func testRunCompletionRunThenZeroStreakClearsEverythingPreviouslyScheduled() {
        let spy = NotificationSchedulingSpy()
        let scheduler = StreakReminderScheduler(notifications: spy, calendar: calendar)

        scheduler.reschedule(currentStreakDays: 5, hasRunToday: true)
        XCTAssertFalse(spy.scheduledIdentifiers.isEmpty)

        // A streak-breaking edge case (defensive): even if callers ever pass 0 after a nonzero streak,
        // everything pending must be cleared, not left stale.
        scheduler.reschedule(currentStreakDays: 0, hasRunToday: false)
        XCTAssertTrue(spy.scheduledIdentifiers.isEmpty)
    }

    /// Regression test for the exact bug found in review (2026-09-14): yesterday's `stop()` schedules a
    /// window that includes TODAY (as "tomorrow" relative to yesterday). Opening the app today, before
    /// running, must not silently drop today's own reminder just because `removeAllPending()` runs again.
    func testForegroundBeforeRunningTodayStillHasTodaysReminderScheduled() throws {
        let spy = NotificationSchedulingSpy()
        let scheduler = StreakReminderScheduler(notifications: spy, calendar: calendar)
        let today = Date()
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let todayIdentifier = StreakReminderScheduler.identifier(for: today, calendar: calendar)

        // Simulates yesterday's stop() — schedules tomorrow (= today) through +daysAhead from yesterday.
        scheduler.reschedule(currentStreakDays: 5, hasRunToday: true, from: yesterday)
        XCTAssertTrue(spy.scheduledIdentifiers.contains(todayIdentifier))

        // Simulates opening the app today, before running — today's reminder must survive.
        scheduler.reschedule(currentStreakDays: 5, hasRunToday: false, from: today)
        XCTAssertTrue(
            spy.scheduledIdentifiers.contains(todayIdentifier),
            "a plain foreground before today's run must not wipe today's own already-scheduled reminder"
        )
    }
}
