import SwiftUI

@main
struct LajuApp: App {
    let persistenceController = PersistenceController.shared
    /// Shown once on first launch (user-flow.md §2.1) — `false` until `OnboardingContainerView` completes.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    private let streakReminderScheduler = StreakReminderScheduler()
    /// T2.3: created once at the app root, injected via `.environmentObject` so any screen (starting with
    /// `OnboardingSignInStep`) can read/act on the current Supabase Auth session.
    @StateObject private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingContainerView { hasCompletedOnboarding = true }
                }
            }
            .environmentObject(authService)
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            // Dark-native by brand identity, not by system-appearance-following (design-notes.md §0).
            .preferredColorScheme(.dark)
        }
        // T1.16 (tech-spec.md §5.2 step 1): app foreground is the OTHER reschedule trigger besides run
        // completion (`RunViewModel.stop()`) — re-derives the N-day projection even if no run happened.
        //
        // Uses `priorStreakDays` (streak ending YESTERDAY), not `StreakTracker.currentStreakDays(asOf: Date())`
        // directly — found in review 2026-09-14: `currentStreakDays(asOf: today)` returns 0 whenever today has
        // no qualifying run yet, which is exactly the common case for a plain foreground (the user hasn't run
        // yet today). Calling `reschedule(currentStreakDays: 0)` would wipe every pending reminder (including
        // today's own, already scheduled by a prior day) and then refuse to reschedule anything — silently
        // disabling the feature for the user it exists to protect. `priorStreakDays` reflects the real,
        // still-alive streak regardless of whether today has been run yet — same query `RunViewModel
        // .beginTracking`/`RunRecovery` already use for this exact reason.
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            let context = persistenceController.container.viewContext
            let qualifyingDates = PersistenceController.runStartDates(
                in: context,
                minDistanceMeters: PointFormula.minDistanceKmForPoints * 1000
            )
            let hasRunToday = StreakTracker.hasRun(on: Date(), runDates: qualifyingDates)
            let priorStreak = PersistenceController.priorStreakDays(asOf: Date(), in: context)
            let streakDays = hasRunToday ? priorStreak + 1 : priorStreak
            streakReminderScheduler.reschedule(currentStreakDays: streakDays, hasRunToday: hasRunToday)
        }
    }
}
