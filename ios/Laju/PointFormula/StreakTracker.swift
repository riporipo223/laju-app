import Foundation

/// T1.4: computes the consecutive-day run streak feeding
/// `PointFormula.calculatePoints`'s `streakDays` parameter (tech-spec.md
/// §2.1/§2.2) — T1.2 stubbed this to a placeholder `0`.
enum StreakTracker {
    /// Counts consecutive calendar days, ending at (and including)
    /// `today`, that have at least one run in `runDates`. Walks backward
    /// one day at a time from `today` and stops at the first day with no
    /// run — so a single missed day resets the streak to whatever
    /// unbroken run of days remains ending at `today`, rather than
    /// looking further back past the gap.
    static func currentStreakDays(
        asOf today: Date,
        runDates: [Date],
        calendar: Calendar = .current
    ) -> Int {
        let runDays = Set(runDates.map { calendar.startOfDay(for: $0) })
        var streak = 0
        var day = calendar.startOfDay(for: today)
        while runDays.contains(day) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }
        return streak
    }

    /// T1.4 DoD item 3 (Round 7 finding N7-P12): exposes "has today already had a qualifying run" directly, so
    /// T1.16's streak-reminder scheduling (tech-spec.md §5.2) doesn't have to re-derive this from `runDates`
    /// itself. Same `runDates` input/semantics as `currentStreakDays` — callers pass the same
    /// `PersistenceController.runStartDates(in:minDistanceMeters:)` result.
    static func hasRun(on day: Date, runDates: [Date], calendar: Calendar = .current) -> Bool {
        runDates.contains { calendar.isDate($0, inSameDayAs: day) }
    }
}
