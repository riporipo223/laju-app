import MapKit
import SwiftUI

/// `RunTrackingView`'s floating top-right nav buttons (Map Type toggle, History) — extracted purely to keep
/// `RunTrackingView.swift` under SwiftLint's `file_length` limit, no behavioral difference from being inline.
///
/// **2026-09-17 (T2.0a):** `profileButton` was removed from here. Profile is now the "You" tab in
/// `RootTabView`, so a floating overlay duplicating it on the Track screen was a second entry point to the
/// same destination. History stays an overlay push — it has no tab of its own and Profile only shows the 5
/// most recent runs, so this remains the only route to the full list.
/// GPS/speed audit (2026-09-25): Standard → Satellite → 3D (MapKit camera pitch, not a separate map
/// type — `RunMapView.pitchDegrees`) → back to Standard. A single tap cycles through all three, no menu
/// needed for 3 options.
enum MapDisplayMode {
    case standard
    case satellite
    case threeD

    var mapType: MKMapType {
        switch self {
        case .standard, .threeD: return .standard
        case .satellite: return .satellite
        }
    }

    var pitchDegrees: CLLocationDirection {
        self == .threeD ? 45 : 0
    }

    var next: MapDisplayMode {
        switch self {
        case .standard: return .satellite
        case .satellite: return .threeD
        case .threeD: return .standard
        }
    }

    var iconName: String {
        switch self {
        case .standard: return "map.fill"
        case .satellite: return "globe.americas.fill"
        case .threeD: return "view.3d"
        }
    }
}

extension RunTrackingView {
    /// T4.21/GPS audit: live map type switcher — Standard/Satellite/3D (phase-4-backlog.md T4.21 v1
    /// scope extended 2026-09-25). Same "standard"/"activity_heat" strings Save Activity's own Map Type
    /// picker uses for the first two; 3D has no server-side equivalent (it's purely a live-tracking
    /// camera effect, not a post attribute).
    var mapTypeButton: some View {
        Button {
            mapDisplayMode = mapDisplayMode.next
        } label: {
            Image(systemName: mapDisplayMode.iconName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LajuColor.accent)
                .padding(10)
                .background(LajuColor.surface, in: Circle())
        }
    }

    /// T1.5's entry point to Run History — floating overlay button now that the nav bar (its old home) is hidden.
    var historyButton: some View {
        NavigationLink {
            RunHistoryView()
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LajuColor.accent)
                .padding(10)
                .background(LajuColor.surface, in: Circle())
        }
    }
}
