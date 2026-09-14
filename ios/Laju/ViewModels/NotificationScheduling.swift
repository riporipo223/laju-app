import Foundation
import UserNotifications

/// T1.16: thin protocol over `UNUserNotificationCenter` — lets `StreakReminderScheduler` be unit-tested with a
/// spy instead of driving real system notification state (same pattern as `AudioCueAnnouncing`, T1.13).
protocol NotificationScheduling {
    func requestAuthorization(completion: @escaping @Sendable (Bool) -> Void)
    func getAuthorizationStatus(completion: @escaping @Sendable (UNAuthorizationStatus) -> Void)
    /// Removes every pending local notification this app has scheduled — safe as a blanket call since Laju
    /// (Fase 1) only ever schedules streak-reminder notifications, nothing else competes for this API.
    func removeAllPending()
    func schedule(identifier: String, dateComponents: DateComponents, title: String, body: String)
}

final class SystemNotificationScheduler: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization(completion: @escaping @Sendable (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func getAuthorizationStatus(completion: @escaping @Sendable (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async { completion(status) }
        }
    }

    func removeAllPending() {
        center.removeAllPendingNotificationRequests()
    }

    func schedule(identifier: String, dateComponents: DateComponents, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }
}
