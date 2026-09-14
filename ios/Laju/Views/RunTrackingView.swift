import Combine
import CoreData
import CoreLocation
import SwiftUI

/// Run Tracking Screen (Fase 1 UI) — replaces the T0.9 debug skeleton (raw meter readouts, no map by default).
/// Structural layout modeled on a Strava pre-run reference screenshot (full-screen map, floating GPS-status
/// banner, floating stats card, large action buttons) — LAYOUT STRUCTURE only, not visual identity.
///
/// **Restyled 2026-09-14** onto the real design system (`Laju/documents/design-notes.md`) — this is the base
/// identity screen (black + neon lime, design-notes.md §5), superseding the 2026-09-13 placeholder system
/// colors/materials this screen shipped with initially.
struct RunTrackingView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var locationService = LocationTrackingService()
    @StateObject private var viewModel: RunViewModelBox

    /// T1.14: the unfinished run (if any) offered for Resume/Save-as-finished at launch — `RunRecovery` decides
    /// which one, this view only presents the choice. `didCheckForRecovery` guards the check to once per launch
    /// (`.onAppear` can otherwise refire, e.g. after the History push returns).
    @State private var recoveryRun: Run?
    @State private var didCheckForRecovery = false

    init() {
        // StateObject can't reference `context` before init, so RunViewModel
        // is created lazily on first appear via RunViewModelBox — see below.
        _viewModel = StateObject(wrappedValue: RunViewModelBox())
    }

    var body: some View {
        NavigationStack {
            trackingContent
                // No system UINavigationBar (on-device feedback: opaque black band cut the map off). "History"
                // moves to a floating overlay button instead — NavigationStack itself still needed for the push.
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Computed properties/methods only — split out purely to keep SwiftLint's `type_body_length` happy after
/// T1.14's recovery UI landed; no behavioral difference from being inline.
private extension RunTrackingView {
    var trackingContent: some View {
        ZStack(alignment: .top) {
            // T1.8/T1.9: same RunMapView as before, now full-screen and
            // always present (not gated on isRunning) so it reads as the
            // screen's background, matching the reference layout.
            //
            // `.ignoresSafeArea()` on ALL edges (not just bottom) — the
            // map must fill the entire screen including under the status
            // bar/notch, now that the nav bar is hidden. MapKit's own
            // required legal-attribution label (bottom-left, can't be
            // removed — Apple's terms) still respects the safe area on
            // its own, so it isn't clipped by this.
            RunMapView(
                currentCoordinate: mapCoordinate,
                routeCoordinates: viewModel.model?.routeCoordinates ?? [],
                headingDegrees: viewModel.model?.currentCourseDegrees
            )
            .ignoresSafeArea()

            if mapCoordinate == nil, gpsStatus != .permissionNeeded {
                mapLoadingOverlay
            }

            VStack {
                HStack {
                    gpsStatusBanner
                    Spacer()
                    profileButton
                    historyButton
                }
                if let notice = locationPermissionNotice {
                    LocationPermissionBanner(notice: notice)
                        .padding(.top, 8)
                }
                Spacer()
                VStack(spacing: 16) {
                    if viewModel.model?.isAutoPaused == true {
                        autoPausedBanner
                    }
                    statsCard
                    actionButtons
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            // Extra bottom padding (beyond the safe area, which the
            // un-ignored VStack already respects) so the button row
            // clears MapKit's legal-attribution label with visible
            // margin instead of crowding it.
            .padding(.bottom, 16)
        }
        .sheet(item: Binding(
            get: { viewModel.model?.completedRunSummary },
            set: { viewModel.model?.completedRunSummary = $0 }
        )) { summary in
            RunSummaryView(summary: summary) {
                viewModel.model?.completedRunSummary = nil
            }
        }
        .onAppear {
            if viewModel.model == nil {
                viewModel.model = RunViewModel(locationService: locationService, context: context)
            }
            if !didCheckForRecovery {
                didCheckForRecovery = true
                recoveryRun = RunRecovery.resolveOnLaunch(in: context)
            }
            // "When In Use" up front — asking for "Always" cold doesn't reliably surface it (Apple shows that
            // upgrade only after When-In-Use is granted). See startTrackingRequestingPermissionIfNeeded below.
            if locationService.authorizationStatus == .notDetermined {
                locationService.requestWhenInUseAuthorization()
            } else {
                requestMapPreviewLocationIfAuthorized()
            }
        }
        // Authorization is granted asynchronously after the system prompt — `.onAppear` alone can't request
        // the preview fix if permission wasn't already granted before this screen opened.
        .onChange(of: locationService.authorizationStatus) { _ in
            requestMapPreviewLocationIfAuthorized()
        }
        .alert(
            "Run belum selesai",
            isPresented: Binding(get: { recoveryRun != nil }, set: {
                if !$0 {
                    recoveryRun = nil
                }
            })
        ) {
            Button("Lanjutkan") {
                if let recoveryRun {
                    viewModel.model?.resumeRecoveredRun(recoveryRun)
                }
                recoveryRun = nil
            }
            Button("Simpan sebagai selesai") {
                if let recoveryRun {
                    viewModel.model?.completedRunSummary = RunRecovery.finalize(recoveryRun, in: context)
                }
                recoveryRun = nil
            }
        } message: {
            Text(recoveryMessage)
        }
    }

    /// T1.14 DoD: the prompt must show when the run started and its last
    /// saved distance — reused formatters (`DistanceFormatter`, same
    /// km-display rule as everywhere else, tech-spec.md §2.1c).
    private var recoveryMessage: String {
        guard let run = recoveryRun else { return "" }
        let startedAtText = run.startedAt.map {
            DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)
        } ?? "waktu tidak diketahui"
        return "Mulai \(startedAtText), jarak tersimpan \(DistanceFormatter.format(meters: run.distanceMeters))."
    }

    private func requestMapPreviewLocationIfAuthorized() {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationService.requestOneTimeLocation()
        default:
            break
        }
    }

    /// Map center source: the active run's live position while tracking
    /// (T1.8, unchanged), otherwise the pre-run one-shot preview fix
    /// (Bagian B) — `LocationTrackingService.lastLocation` already
    /// published, no new state.
    private var mapCoordinate: CLLocationCoordinate2D? {
        if viewModel.model?.isRunning == true {
            return viewModel.model?.currentCoordinate
        }
        return locationService.lastLocation?.coordinate
    }

    private var mapLoadingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(LajuColor.accent)
            Text("Mencari lokasi kamu…")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LajuColor.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LajuColor.background.opacity(0.55))
        .ignoresSafeArea()
    }

    // MARK: - GPS status banner

    /// Derived entirely from existing published state — no new location state added. `.ready`/`.reduced` reuse
    /// the same ~10m "settled fix" notion as `RunViewModel.anchorAccuracyThresholdMeters` (tech-spec.md §2.1b).
    private enum GPSStatus: Equatable {
        case permissionNeeded, searching, ready, reduced

        var label: String {
            switch self {
            case .permissionNeeded: "Izin lokasi dibutuhkan"
            case .searching: "Mencari sinyal GPS…"
            case .ready: "GPS siap"
            case .reduced: "Akurasi GPS kurang optimal"
            }
        }

        var color: Color {
            switch self {
            case .permissionNeeded: LajuColor.textDisabled
            case .searching: LajuColor.warning
            case .ready: LajuColor.accent
            case .reduced: LajuColor.warning
            }
        }

        var systemImage: String {
            self == .permissionNeeded ? "location.slash" : "location.fill"
        }
    }

    private var gpsStatus: GPSStatus {
        switch locationService.authorizationStatus {
        case .denied, .restricted, .notDetermined:
            return .permissionNeeded
        default:
            break
        }
        guard viewModel.model?.isRunning == true else {
            return locationService.lastLocation == nil ? .searching : .ready
        }
        guard let lastLocation = locationService.lastLocation else { return .searching }
        return lastLocation.horizontalAccuracy <= 10 ? .ready : .reduced
    }

    /// T1.15: separate from `gpsStatus` above (that one is about live signal quality, this is about the
    /// authorization grant itself) — `nil` for `.authorizedAlways`/`.notDetermined` (nothing to show).
    private var locationPermissionNotice: LocationPermissionNotice? {
        LocationPermissionNotice.notice(for: locationService.authorizationStatus)
    }

    private var gpsStatusBanner: some View {
        Label(gpsStatus.label, systemImage: gpsStatus.systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(gpsStatus == .ready ? LajuColor.background : LajuColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(gpsStatus.color, in: Capsule())
    }

    /// T1.11 (product-spec §4.11 AC2): a distinct indicator so the user isn't confused why the run stopped by
    /// itself — the Pause/Resume button alone always just says "Resume" regardless of why it's paused.
    /// `warning` amber (design-notes.md §1) — not `accent`, so it never competes with the brand hero color.
    private var autoPausedBanner: some View {
        Label("Auto-paused — kamu berhenti bergerak", systemImage: "pause.circle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(LajuColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(LajuColor.warning, in: Capsule())
    }

    // MARK: - Stats card

    /// `TimelineView` ticks this every second so Time keeps moving even
    /// between GPS fixes (`liveActiveDuration()` is a pure wall-clock
    /// computation, see its doc) — Distance/Pace update whenever it also
    /// happens to redraw, same as before.
    private var statsCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 0) {
                statColumn(label: "Time", value: DurationFormatter.format(seconds: liveDuration), isHero: false)
                Divider().frame(height: 40).overlay(LajuColor.hairline)
                // Distance is THE hero stat (design-notes.md §5) — lime, the only one of the three.
                statColumn(label: "Distance", value: DistanceFormatter.format(meters: liveDistanceMeters), isHero: true)
                Divider().frame(height: 40).overlay(LajuColor.hairline)
                statColumn(label: "Pace", value: livePaceLabel, isHero: false)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(LajuColor.accent)
                    .frame(height: 2)
                    .padding(.horizontal, 24)
                    .padding(.top, 1)
            }
        }
    }

    private func statColumn(label: String, value: String, isHero: Bool) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(LajuFont.sectionNumber)
                .foregroundStyle(isHero ? LajuColor.accent : LajuColor.textPrimary)
            LajuLabelText(text: label)
        }
        .frame(maxWidth: .infinity)
    }

    private var liveDuration: TimeInterval {
        viewModel.model?.liveActiveDuration() ?? 0
    }

    private var liveDistanceMeters: Double {
        viewModel.model?.distanceMeters ?? 0
    }

    private var livePaceLabel: String {
        guard liveDistanceMeters > 0 else { return "—:— /km" }
        let secPerKm = liveDuration / (liveDistanceMeters / 1000)
        return PaceFormatter.format(secPerKm: secPerKm)
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        Group {
            if viewModel.model?.isRunning == true {
                // Pause/Resume — visually distinct from Finish (T1.2b):
                // secondary (dark, lime top-line) vs Finish's destructive
                // red, so they're never mistaken for one another.
                HStack(spacing: 12) {
                    Button(viewModel.model?.isPaused == true ? "Resume" : "Pause") {
                        guard let model = viewModel.model else { return }
                        if model.isPaused {
                            model.resume()
                        } else {
                            model.pause()
                        }
                    }
                    .buttonStyle(.lajuSecondary)

                    Button("Finish") {
                        viewModel.model?.stop()
                    }
                    .buttonStyle(.lajuDestructive)
                }
                .frame(maxWidth: .infinity)
            } else {
                Button("Start") {
                    guard let model = viewModel.model else { return }
                    startTrackingRequestingPermissionIfNeeded(model)
                }
                .buttonStyle(.lajuPrimary)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// T0.9's background test needs "Always", not just "When In Use" — only requested once When-In-Use is
    /// already granted (see .onAppear above), since Apple only surfaces the Always upgrade after that.
    private func startTrackingRequestingPermissionIfNeeded(_ model: RunViewModel) {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse:
            locationService.requestAlwaysAuthorization()
        case .notDetermined:
            locationService.requestWhenInUseAuthorization()
        default:
            break
        }
        model.start()
    }
}

/// `RunViewModel` needs `context` (an environment value), unavailable at `View.init` time — this box defers
/// creation to `.onAppear` while still giving SwiftUI a stable `@StateObject`. Also forwards `model`'s own
/// `objectWillChange` up through this box's own — found necessary 2026-09-13: `@StateObject` only subscribes to
/// the object it directly owns, not to a nested `ObservableObject` inside a `@Published` property. Every OTHER
/// action happened to still re-render the view because it also touched `locationService`'s own `@Published`
/// state — Done on Run Summary (only mutates `model.completedRunSummary`) didn't, so the sheet never dismissed
/// without a force-quit, until this forward was added.
private final class RunViewModelBox: ObservableObject {
    @Published var model: RunViewModel? {
        didSet { forwardModelChanges() }
    }

    private var modelCancellable: AnyCancellable?

    private func forwardModelChanges() {
        modelCancellable = model?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}

#Preview("Idle") {
    RunTrackingView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}

#Preview("Idle — Dark") {
    RunTrackingView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .preferredColorScheme(.dark)
}
