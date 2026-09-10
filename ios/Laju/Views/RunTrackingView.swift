import CoreData
import SwiftUI

/// T0.9 skeleton screen: Start/Stop only, enough to drive
/// `LocationTrackingService` for the background-survival/battery test.
/// Full run-summary UI (points, pace) is T1.2 (Fase 1), not this task.
struct RunTrackingView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var locationService = LocationTrackingService()
    @StateObject private var viewModel: RunViewModelBox

    init() {
        // StateObject can't reference `context` before init, so RunViewModel
        // is created lazily on first appear via RunViewModelBox — see below.
        _viewModel = StateObject(wrappedValue: RunViewModelBox())
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(viewModel.model?.isRunning == true ? "Tracking…" : "Stopped")
                .font(.title2)

            Text("Points captured: \(viewModel.model?.pointCount ?? 0)")
            Text(String(format: "Distance: %.0f m", Double(viewModel.model?.distanceMeters ?? 0)))
            Text("Location permission: \(authorizationLabel)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(viewModel.model?.isRunning == true ? "Stop" : "Start") {
                guard let model = viewModel.model else { return }
                if model.isRunning {
                    model.stop()
                } else {
                    startTrackingRequestingPermissionIfNeeded(model)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear {
            if viewModel.model == nil {
                viewModel.model = RunViewModel(locationService: locationService, context: context)
            }
            // Request "When In Use" up front — asking for "Always" cold,
            // before the user has granted anything, doesn't reliably
            // surface the Always option (Apple shows that upgrade only
            // after When-In-Use is already granted). See startTracking...
            // below for the second step.
            if locationService.authorizationStatus == .notDetermined {
                locationService.requestWhenInUseAuthorization()
            }
        }
    }

    /// T0.9's background test needs "Always" authorization, not just
    /// "When In Use" — the latter stops delivering updates once the app
    /// is backgrounded/locked, which would make the test fail for a
    /// permission reason, not a real CLLocationManager background-mode
    /// reason. Requesting "Always" only works reliably once "When In
    /// Use" is already granted (see .onAppear above), so this checks
    /// that before escalating.
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

    private var authorizationLabel: String {
        switch locationService.authorizationStatus {
        case .notDetermined: "not requested yet"
        case .authorizedWhenInUse: "When In Use only — background test needs Always"
        case .authorizedAlways: "Always — ready for background test"
        case .denied: "Denied — enable in Settings"
        case .restricted: "Restricted"
        @unknown default: "unknown"
        }
    }
}

/// `RunViewModel` needs `context` (an environment value) to construct,
/// which isn't available at `View.init` time — this box defers creation
/// to `.onAppear` while still giving SwiftUI a stable `@StateObject`.
private final class RunViewModelBox: ObservableObject {
    @Published var model: RunViewModel?
}

#Preview {
    RunTrackingView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
