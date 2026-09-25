import CoreLocation
import SwiftUI
import UserNotifications

/// T1.2: the "instant reward" screen — appears immediately on Stop (product-spec.md AC 4.3.1: within 2s).
/// T1.3 adds level-up, T1.4 adds streak. **Restyled 2026-09-14** onto the real design system
/// (design-notes.md §5) — confetti burst added as the deliberate "reward moment" motion (§4), triggered by
/// this view simply appearing (which already happens the instant Finish/Stop is tapped — see
/// `RunViewModel.stop()` setting `completedRunSummary` synchronously), not a new signal.
struct RunSummaryView: View {
    let summary: RunSummary
    let onDismiss: () -> Void
    @State private var confettiActive = false
    /// T1.16: contextual permission prompt (product-spec §4.15's pattern) — only offered when there's an
    /// actual streak to protect and the system hasn't already been asked. `nil` (not `.notDetermined`) until
    /// the async check resolves — found in review 2026-09-14: defaulting to `.notDetermined` made the prompt
    /// flash on for a frame even for users who'd already granted/denied notifications.
    @State private var notificationAuthStatus: UNAuthorizationStatus?
    private let streakReminderScheduler = StreakReminderScheduler()

    var body: some View {
        ZStack {
            LajuColor.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Text("Run Complete")
                        .font(LajuFont.heading)
                        .foregroundStyle(LajuColor.textPrimary)

                    routeMap

                    statGrid

                    if !summary.splits.isEmpty {
                        splitsList
                    }

                    pointsHero

                    if let leveledUpTo = summary.leveledUpTo {
                        levelUpCard(leveledUpTo)
                    }

                    if summary.streakDays >= 1, notificationAuthStatus == .notDetermined {
                        streakReminderPrompt
                    }

                    Button("Done", action: onDismiss)
                        .buttonStyle(.lajuPrimary)
                }
                .padding()
            }

            ConfettiBurstView(isActive: confettiActive)
                .ignoresSafeArea()
        }
        .onAppear {
            confettiActive = true
            streakReminderScheduler.authorizationStatus { status in
                Task { @MainActor in notificationAuthStatus = status }
            }
        }
    }

    /// T1.16 AC2/product-spec §4.15 pattern: explain WHY before the system prompt, not a bare permission
    /// dialog. Tapping requests authorization, then immediately reschedules using this run's own streak so
    /// the very first reminder window is set up without waiting for the next run/foreground.
    private var streakReminderPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Jangan sampai streak putus")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LajuColor.textPrimary)
            Text("Aktifkan reminder — Laju akan ingetin kamu kalau belum lari hari ini dan streak berisiko putus.")
                .font(.caption)
                .foregroundStyle(LajuColor.textSecondary)
            Button("Aktifkan Reminder") {
                let streakDays = summary.streakDays
                let hasRunToday = summary.distanceMeters / 1000 >= PointFormula.minDistanceKmForPoints
                streakReminderScheduler.requestAuthorization { granted in
                    Task { @MainActor in
                        notificationAuthStatus = granted ? .authorized : .denied
                        if granted {
                            streakReminderScheduler.reschedule(currentStreakDays: streakDays, hasRunToday: hasRunToday)
                        }
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(LajuColor.accent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    /// T1.9, product-spec.md §4.9 AC1: static route map — a run with fewer than 2 points can't draw a line,
    /// shows a clear empty state instead of a blank/broken map (AC3). Route glow is `RunMapView`'s own styling.
    @ViewBuilder
    private var routeMap: some View {
        if summary.routeCoordinates.count > 1 {
            RunMapView(currentCoordinate: nil, routeCoordinates: summary.routeCoordinates)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        } else {
            VStack(spacing: 4) {
                Image(systemName: "location.slash")
                    .font(.title2)
                    .foregroundStyle(LajuColor.textSecondary)
                Text("No route recorded for this run")
                    .font(.footnote)
                    .foregroundStyle(LajuColor.textSecondary)
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var statGrid: some View {
        VStack(spacing: 0) {
            summaryRow("Distance", DistanceFormatter.format(meters: summary.distanceMeters))
            Divider().overlay(LajuColor.hairline)
            summaryRow("Duration", DurationFormatter.format(seconds: summary.durationSeconds))
            Divider().overlay(LajuColor.hairline)
            summaryRow(
                "Speed",
                summary.distanceMeters > 0 ? SpeedFormatter.format(secPerKm: summary.avgPaceSecPerKm) : "—"
            )
            Divider().overlay(LajuColor.hairline)
            summaryRow("Streak", "\(summary.streakDays) day\(summary.streakDays == 1 ? "" : "s")")
            Divider().overlay(LajuColor.hairline)
            summaryRow("Elevation Gain", ElevationFormatter.format(meters: summary.elevationGainMeters))
            Divider().overlay(LajuColor.hairline)
            summaryRow("Elevation Loss", ElevationFormatter.format(meters: summary.elevationLossMeters))
        }
        .padding(.vertical, 4)
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1)
                .fill(LajuColor.accent)
                .frame(height: 2)
                .padding(.horizontal, 24)
                .padding(.top, 1)
        }
    }

    /// T1.10, product-spec.md §4.10: per-km splits — empty when a run never completed/started a partial km.
    private var splitsList: some View {
        VStack(spacing: 4) {
            ForEach(summary.splits) { split in
                HStack {
                    Text("Km \(split.splitNumber)\(split.isPartial ? " (partial)" : "")")
                        .foregroundStyle(LajuColor.textSecondary)
                    Spacer()
                    Text(SpeedFormatter.format(secPerKm: split.avgPaceSecPerKm))
                        .bold()
                        .foregroundStyle(LajuColor.textPrimary)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var pointsHero: some View {
        VStack(spacing: 2) {
            Text(String(format: "+%.1f", summary.estimatedPoints))
                .font(LajuFont.heroNumber)
                .foregroundStyle(LajuColor.accent)
            LajuLabelText(text: "Points")
        }
        .padding(.top, 8)
    }

    /// T1.3, product-spec AC 4.4.2 — level-up is `success`, which design-notes.md §1 deliberately reuses
    /// `accent` for (leveling up IS the core reward, not a separate color).
    private func levelUpCard(_ leveledUpTo: LevelThreshold) -> some View {
        VStack(spacing: 4) {
            Text("Level Up!")
                .font(LajuFont.heading)
            Text("Level \(leveledUpTo.level) — \(leveledUpTo.title)")
                .font(.headline)
        }
        .foregroundStyle(LajuColor.background)
        .frame(maxWidth: .infinity)
        .padding()
        .background(LajuColor.accent, in: RoundedRectangle(cornerRadius: 20))
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            LajuLabelText(text: label)
            Spacer()
            Text(value)
                .font(LajuFont.sectionNumber)
                .foregroundStyle(LajuColor.textPrimary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

#Preview {
    RunSummaryView(
        summary: RunSummary(
            distanceMeters: 5230,
            durationSeconds: 1830,
            avgPaceSecPerKm: 350,
            estimatedPoints: 6.2,
            leveledUpTo: LevelThreshold(level: 2, pointsRequired: 100, title: "Rajin"),
            streakDays: 3,
            routeCoordinates: [
                CLLocationCoordinate2D(latitude: -7.7057, longitude: 110.4084),
                CLLocationCoordinate2D(latitude: -7.7066, longitude: 110.4084),
                CLLocationCoordinate2D(latitude: -7.7070, longitude: 110.4090)
            ],
            splits: [
                RunSplit(splitNumber: 1, distanceMeters: 1005, durationSeconds: 340, isPartial: false),
                RunSplit(splitNumber: 2, distanceMeters: 1000, durationSeconds: 355, isPartial: false),
                RunSplit(splitNumber: 3, distanceMeters: 230, durationSeconds: 90, isPartial: true)
            ],
            elevationGainMeters: 42,
            elevationLossMeters: 18
        ),
        onDismiss: {}
    )
}
