import SwiftUI

@main
struct LajuApp: App {
    let persistenceController: PersistenceController
    /// Shown once on first launch (user-flow.md §2.1) — `false` until `OnboardingContainerView` completes.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    private let streakReminderScheduler = StreakReminderScheduler()
    /// T2.3: created once at the app root, injected via `.environmentObject` so any screen (starting with
    /// `OnboardingSignInStep`) can read/act on the current Supabase Auth session.
    @StateObject private var authService = AuthService()
    /// T2.14: background sync queue for offline-recorded runs — starts observing connectivity immediately
    /// on creation (`SyncService.init`), so a run recorded fully offline syncs as soon as the network
    /// returns without needing any view to appear first.
    @StateObject private var syncService: SyncService
    /// T2.16: server-authoritative progress (points/level/trust_score) for `ProfileView`. Owned here, not
    /// inside the screen, so `refresh()` stays externally callable (T2.14d's future reconciliation loop).
    @StateObject private var progressViewModel: ProgressViewModel
    /// T2.14d: status reconciliation loop — triggered from `syncService.onCycleFinished`, which covers both
    /// app open (`scenePhase == .active` → `syncPendingRuns()`) and connectivity-restored sync cycles.
    private let reconciliationService: ReconciliationService
    /// T2.22: in-app account deletion (App Store Guideline 5.1.1(v)) — owned here so it can reset the other
    /// root-owned state (`progressViewModel`) after a successful deletion.
    @StateObject private var accountDeletion: AccountDeletionService

    init() {
        let controller = PersistenceController.shared
        persistenceController = controller
        let progress = ProgressViewModel()
        _progressViewModel = StateObject(wrappedValue: progress)
        let reconciliation = ReconciliationService(
            persistence: controller,
            onRunsChanged: { await progress.refresh() }
        )
        reconciliationService = reconciliation
        let sync = SyncService(context: controller.container.viewContext)
        sync.onCycleFinished = { await reconciliation.reconcileIfNeeded() }
        _syncService = StateObject(wrappedValue: sync)
        _accountDeletion = StateObject(wrappedValue: AccountDeletionService(
            persistence: controller,
            onDeleted: { progress.reset() }
        ))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingContainerView { hasCompletedOnboarding = true }
                } else if !authService.hasCheckedInitialSession {
                    // Brief window on cold start before the SDK's Keychain-backed session restore reports
                    // in — avoids flashing ReturningSignInView for an already-signed-in returning user.
                    ProgressView().tint(LajuColor.accent)
                } else if authService.isSignedIn {
                    RootTabView()
                } else {
                    // 2026-09-24 (Bagian B item 7): onboarded before, signed out now (explicit Logout or an
                    // expired session) — skip the full onboarding flow, straight to sign-in.
                    ReturningSignInView()
                }
            }
            .environmentObject(authService)
            .environmentObject(progressViewModel)
            .environmentObject(accountDeletion)
            .environmentObject(syncService)
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
            // T2.14: covers "already online when the app opens" — NWPathMonitor only fires on a
            // *transition* to satisfied, not on an already-satisfied path observed for the first time here.
            Task { await syncService.syncPendingRuns() }
        }
    }
}
