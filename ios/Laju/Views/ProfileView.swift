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

    /// T1.13 AC2: no dedicated Settings screen exists yet — Profile is the closest existing home for this
    /// toggle. Same `UserDefaults` key `AudioCueService.isEnabled` reads/writes, not a separate flag.
    @AppStorage(AudioCueService.enabledDefaultsKey) private var audioCuesEnabled = true

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                streakSection
                levelSection
                settingsSection
                recentRunsSection
            }
            .padding()
        }
        .background(LajuColor.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .toolbarColorScheme(.dark, for: .navigationBar)
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

    private var levelSection: some View {
        let level = LevelProgression.currentLevel(totalPoints: totalPoints)
        let toNext = LevelProgression.pointsToNextLevel(totalPoints: totalPoints)
        let currentThresholdPoints = level.pointsRequired
        let nextThresholdPoints = totalPoints + toNext
        let progress = toNext > 0
            ? (totalPoints - currentThresholdPoints) / max(nextThresholdPoints - currentThresholdPoints, 1)
            : 1

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Level \(level.level) — \(level.title)")
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

    // MARK: - Settings

    private var settingsSection: some View {
        Toggle("Audio Cues", isOn: $audioCuesEnabled)
            .tint(LajuColor.accent)
            .foregroundStyle(LajuColor.textPrimary)
            .padding()
            .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
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
    }
    .preferredColorScheme(.dark)
}
