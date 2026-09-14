import CoreLocation
@testable import Laju
import UserNotifications
import XCTest

private final class NotificationSchedulingSpy: NotificationScheduling {
    private(set) var scheduledIdentifiers: [String] = []
    private(set) var removeAllPendingCallCount = 0

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        completion(true)
    }

    func getAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        completion(.authorized)
    }

    func removeAllPending() {
        removeAllPendingCallCount += 1
        scheduledIdentifiers.removeAll()
    }

    func schedule(identifier: String, dateComponents _: DateComponents, title _: String, body _: String) {
        scheduledIdentifiers.append(identifier)
    }
}

/// T1.16 DoD: `RunViewModel.stop()` must reschedule streak reminders using THIS run's own final streak — a
/// qualifying run today should immediately re-derive the N-day window, not wait for the next app foreground.
final class RunViewModelStreakReminderTests: XCTestCase {
    func testStopReschedulesUsingThisRunsFinalStreak() {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let spy = NotificationSchedulingSpy()
        let scheduler = StreakReminderScheduler(notifications: spy)
        let viewModel = RunViewModel(
            locationService: locationService,
            context: context,
            streakReminderScheduler: scheduler
        )

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7157, longitude: 110.4084))
        viewModel.stop()

        // A qualifying run today (streakDays >= 1) must produce a fresh reminder window, not zero.
        XCTAssertEqual(spy.removeAllPendingCallCount, 1)
        XCTAssertEqual(spy.scheduledIdentifiers.count, StreakReminderScheduler.daysAhead)
    }

    func testStopWithNoMovementSchedulesNothing() {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let spy = NotificationSchedulingSpy()
        let scheduler = StreakReminderScheduler(notifications: spy)
        let viewModel = RunViewModel(
            locationService: locationService,
            context: context,
            streakReminderScheduler: scheduler
        )

        viewModel.start()
        viewModel.stop()

        // Zero-distance run never qualifies (PointFormula.minDistanceKmForPoints) — no streak to protect.
        XCTAssertTrue(spy.scheduledIdentifiers.isEmpty)
    }
}
