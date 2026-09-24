import CoreData
import SwiftUI

/// Profile/Level screen (new, 2026-09-14) — design-notes.md §5, streak-grid heatmap referencing #6(top).
/// Reuses existing data sources only: `StreakTracker`/`PersistenceController` for streak, `LevelProgression`
/// for level/points, and the same `Run` fetch `RunHistoryView` uses for the recent-runs list — no new data
/// source, no new tracking/point/streak logic.
struct ProfileView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Run.startedAt, ascending: false)]
    )
    private var runs: FetchedResults<Run>

    /// T2.16: server-authoritative points/level, owned at the app root (`LajuApp`) so `refresh()` stays
    /// externally callable. `nil` `serverProgress` (never fetched yet, or offline) falls back to the local
    /// `runs`-derived estimate below — same values this screen showed before T2.16 existed.
    @EnvironmentObject private var progressViewModel: ProgressViewModel
    @EnvironmentObject private var accountDeletion: AccountDeletionService
    @State private var showDeleteConfirmation = false
    @State private var showDeleteFailure = false

    /// T1.13 AC2: no dedicated Settings screen exists yet — Profile is the closest existing home for this
    /// toggle. Same `UserDefaults` key `AudioCueService.isEnabled` reads/writes, not a separate flag.
    @AppStorage(AudioCueService.enabledDefaultsKey) private var audioCuesEnabled = true

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                streakSection
                levelSection
                #if DEBUG
                    clubSection
                #endif
                settingsSection
                accountSection
                recentRunsSection
            }
            .padding()
        }
        .background(LajuColor.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await progressViewModel.refresh()
        }
        // T2.22: two deliberate steps (button, then a destructive confirmation) — never a single-tap
        // irreversible action.
        .alert("Hapus akun?", isPresented: $showDeleteConfirmation) {
            Button("Batal", role: .cancel) {}
            Button("Hapus permanen", role: .destructive) {
                Task {
                    if await accountDeletion.deleteAccount() == false {
                        showDeleteFailure = true
                    }
                }
            }
        } message: {
            Text("Akunmu, poin, dan semua runmu dihapus permanen dan tidak bisa dikembalikan. "
                + "Riwayat rute di perangkat ini juga dihapus.")
        }
        .alert("Gagal menghapus akun", isPresented: $showDeleteFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Akunmu belum dihapus dan datamu masih utuh. Periksa koneksi dan coba lagi.")
        }
    }

    // MARK: - Streak

    private var qualifyingRunDates: [Date] {
        runs
            .filter { $0.distanceMeters >= PointFormula.minDistanceKmForPoints * 1000 }
            .compactMap(\.startedAt)
    }

    private var currentStreakDays: Int {
        StreakTracker.currentStreakDays(asOf: Date(), runDates: qualifyingRunDates)
    }

    /// Oldest-to-newest, ending today — chunked into 7-day rows for the grid below.
    private var last35Days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0 ..< 35).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private var streakSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("\(currentStreakDays)")
                    .font(LajuFont.heroNumber)
                    .foregroundStyle(LajuColor.accent)
                LajuLabelText(text: "Day Streak")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(last35Days, id: \.self) { day in
                    StreakDayDot(
                        isQualifying: StreakTracker.hasRun(on: day, runDates: qualifyingRunDates),
                        isToday: Calendar.current.isDateInToday(day)
                    )
                }
            }
        }
        .padding()
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1)
                .fill(LajuColor.accent)
                .frame(height: 2)
                .padding(.horizontal, 24)
                .padding(.top, 1)
        }
    }

    // MARK: - Level

    private var totalPoints: Double {
        runs.reduce(0) { $0 + $1.estimatedPoints }
    }

    /// T2.16: server-derived values when available (`progressViewModel.serverProgress != nil`), otherwise
    /// the same local `runs`-derived estimate this screen used before T2.16 — `levelCard` renders either.
    @ViewBuilder
    private var levelSection: some View {
        if let server = progressViewModel.serverProgress {
            levelCard(
                levelNumber: server.currentLevel,
                title: LevelProgression.title(forLevel: server.currentLevel),
                totalPoints: Double(server.totalPoints),
                toNext: Double(server.pointsToNextLevel)
            )
        } else {
            let level = LevelProgression.currentLevel(totalPoints: totalPoints)
            levelCard(
                levelNumber: level.level,
                title: level.title,
                totalPoints: totalPoints,
                toNext: LevelProgression.pointsToNextLevel(totalPoints: totalPoints)
            )
        }
    }

    private func levelCard(levelNumber: Int, title: String, totalPoints: Double, toNext: Double) -> some View {
        let currentThresholdPoints = LevelProgression.levelThresholds
            .first(where: { $0.level == levelNumber })?.pointsRequired ?? 0
        let nextThresholdPoints = totalPoints + toNext
        let progress = toNext > 0
            ? (totalPoints - currentThresholdPoints) / max(nextThresholdPoints - currentThresholdPoints, 1)
            : 1

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Level \(levelNumber) — \(title)")
                    .font(LajuFont.heading)
                    .foregroundStyle(LajuColor.textPrimary)
                Text("\(Int(totalPoints)) total points")
                    .font(.footnote)
                    .foregroundStyle(LajuColor.textSecondary)
            }

            ProgressView(value: min(max(progress, 0), 1))
                .tint(LajuColor.accent)
                .background(LajuColor.hairline, in: Capsule())

            if toNext > 0 {
                Text("\(Int(toNext)) points to next level")
                    .font(.caption)
                    .foregroundStyle(LajuColor.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1)
                .fill(LajuColor.accent)
                .frame(height: 2)
                .padding(.horizontal, 24)
                .padding(.top, 1)
        }
    }

    // MARK: - Club

    #if DEBUG
        /// T4.2c scaffold entry: "Club Saya" in the You tab (product-spec.md §4.24 AC19). DEBUG-only — Club
        /// (T4.1) isn't built and the Club War backend can't work yet (T4.2a unapplied, Premium denied until T4.20).
        private var clubSection: some View {
            NavigationLink {
                ClubWarView()
            } label: {
                HStack {
                    Text("Club Saya")
                        .font(LajuFont.heading)
                        .foregroundStyle(LajuColor.textPrimary)
                    Spacer()
                    Text("Club War")
                        .font(LajuFont.label)
                        .foregroundStyle(LajuColor.textSecondary)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(LajuColor.textSecondary)
                }
                .padding()
                .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    #endif

    // MARK: - Settings

    private var settingsSection: some View {
        Toggle("Audio Cues", isOn: $audioCuesEnabled)
            .tint(LajuColor.accent)
            .foregroundStyle(LajuColor.textPrimary)
            .padding()
            .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Account

    /// T2.22 (product-spec.md §4.17): initiate account deletion from inside the app.
    private var accountSection: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            HStack {
                if accountDeletion.isDeleting {
                    ProgressView().tint(LajuColor.error)
                }
                Text(accountDeletion.isDeleting ? "Menghapus akun…" : "Hapus akun")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(LajuDestructiveButtonStyle())
        .disabled(accountDeletion.isDeleting)
    }

    // MARK: - Recent runs

    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LajuLabelText(text: "Recent Runs")
            if runs.isEmpty {
                Text("Belum ada run.")
                    .font(.subheadline)
                    .foregroundStyle(LajuColor.textSecondary)
            } else {
                ForEach(runs.prefix(5)) { run in
                    HStack {
                        Text(run.startedAt ?? Date(), style: .date)
                            .foregroundStyle(LajuColor.textPrimary)
                        Spacer()
                        Text(DistanceFormatter.format(meters: run.distanceMeters))
                            .foregroundStyle(LajuColor.textSecondary)
                        Text(String(format: "%.1f pts", run.estimatedPoints))
                            .foregroundStyle(LajuColor.accent)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct StreakDayDot: View {
    let isQualifying: Bool
    let isToday: Bool

    var body: some View {
        Circle()
            .fill(isQualifying ? LajuColor.accent : Color.clear)
            .overlay {
                Circle().stroke(isToday ? LajuColor.accent : LajuColor.hairline, lineWidth: isQualifying ? 0 : 1.5)
            }
            .frame(height: 20)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .environmentObject(ProgressViewModel())
            .environmentObject(AccountDeletionService(persistence: PersistenceController.shared))
    }
    .preferredColorScheme(.dark)
}
