import Foundation
import UserNotifications

/// T1.16: local streak-reminder scheduling (product-spec.md §4.16, tech-spec.md §5.2). Schedules N days ahead
/// at once — NOT a single notification re-derived only "on run completion and app foreground" (Round 7
/// finding B7-6): the user this feature targets (streak at risk, hasn't run today) is exactly the user least
/// likely to open the app that day, so a reschedule-only-on-open design would never fire for them. Instead,
/// every reschedule call fills a full `daysAhead`-day window; each individual day's own notification, once
/// scheduled, survives independently of whether the app is ever opened again before it fires.
/// `@unchecked Sendable`: all stored state (`notifications`, `calendar`) is set once at init and never mutated
/// afterward — every method just delegates to `notifications`, whose own completions already hop back to the
/// main thread (`SystemNotificationScheduler`). Needed so this can be captured from the `@Sendable` completion
/// closures `RunSummaryView`'s permission-request flow passes to `requestAuthorization`/`authorizationStatus`.
final class StreakReminderScheduler: @unchecked Sendable {
    static let daysAhead = 7
    /// Evening local time — tuning candidate, same status as `PointFormula`'s pace-bracket constants: a
    /// reasonable v1 default, not verified against real user data yet.
    static let reminderHour = 20
    private static let identifierPrefix = "streak-reminder-"

    private let notifications: NotificationScheduling
    private let calendar: Calendar

    init(notifications: NotificationScheduling = SystemNotificationScheduler(), calendar: Calendar = .current) {
        self.notifications = notifications
        self.calendar = calendar
    }

    /// Call after every run completion (`RunViewModel.stop()`) and on every app foreground (tech-spec.md
    /// §5.2 step 1). Always clears every previously-scheduled reminder first — a fresh run just now (or the
    /// app simply being reopened to re-derive the projection) invalidates any stale window, so this never
    /// stacks duplicate notifications for the same future date.
    ///
    /// **`hasRunToday` matters, found 2026-09-14 in review**: `removeAllPending()` above wipes TODAY's own
    /// already-scheduled reminder (placed there by a PRIOR day's call, as that day's "tomorrow") on every
    /// call — including a plain app foreground with no run. If the loop only ever rebuilt tomorrow-onward, a
    /// user who simply opens the app today, before running, would silently lose today's own reminder with
    /// nothing re-adding it — the exact user this feature exists to protect. So when `!hasRunToday`, today
    /// (offset 0) is included in the rebuilt window; when a qualifying run just completed today, today is
    /// correctly skipped (product-spec §4.16: no reminder on a day already run).
    ///
    /// `currentStreakDays == 0` (never run / no active streak) schedules nothing (Round 7 finding N7-12): this
    /// feature protects an existing streak from breaking, it does not drive first-run acquisition — that is
    /// onboarding's job, not this one's.
    func reschedule(currentStreakDays: Int, hasRunToday: Bool, from now: Date = Date()) {
        notifications.removeAllPending()
        guard currentStreakDays > 0 else { return }
        let startOffset = hasRunToday ? 1 : 0
        for offset in startOffset ... Self.daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            scheduleReminder(for: day)
        }
    }

    /// Contextual permission request (product-spec §4.15's pattern, reused here per tech-spec §5.2) — call
    /// this from a UI moment that explains WHY first (e.g. "aktifkan reminder biar streak nggak putus"), not
    /// unconditionally at app launch.
    func requestAuthorization(completion: @escaping @Sendable (Bool) -> Void = { _ in }) {
        notifications.requestAuthorization(completion: completion)
    }

    func authorizationStatus(completion: @escaping @Sendable (UNAuthorizationStatus) -> Void) {
        notifications.getAuthorizationStatus(completion: completion)
    }

    private func scheduleReminder(for day: Date) {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = Self.reminderHour
        components.minute = 0
        notifications.schedule(
            identifier: Self.identifier(for: day, calendar: calendar),
            dateComponents: components,
            title: "Jangan putus streak-nya!",
            body: "Kamu belum lari hari ini — lari sekarang biar streak tetap jalan."
        )
    }

    /// Per-date identifier (not one static identifier) — several future days are scheduled at once and must
    /// not overwrite each other (tech-spec.md §5.2 step 1).
    static func identifier(for day: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let dayOfMonth = components.day ?? 0
        return identifierPrefix + String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }
}
