import MapKit
import SwiftUI

/// `RunTrackingView`'s floating top-right nav buttons (Map Type toggle, History) — extracted purely to keep
/// `RunTrackingView.swift` under SwiftLint's `file_length` limit, no behavioral difference from being inline.
///
/// **2026-09-17 (T2.0a):** `profileButton` was removed from here. Profile is now the "You" tab in
/// `RootTabView`, so a floating overlay duplicating it on the Track screen was a second entry point to the
/// same destination. History stays an overlay push — it has no tab of its own and Profile only shows the 5
/// most recent runs, so this remains the only route to the full list.
extension RunTrackingView {
    /// T4.21: live map type switcher (v1 scope — Standard/Satellite only, phase-4-backlog.md T4.21; same
    /// two values Save Activity's own Map Type picker offers, kept in sync there via the "standard"/
    /// "activity_heat" string this maps to/from). A single tap toggles between the two — no menu needed for
    /// just 2 options.
    var mapTypeButton: some View {
        Button {
            mapType = mapType == .standard ? .satellite : .standard
        } label: {
            Image(systemName: mapType == .standard ? "globe.americas.fill" : "map.fill")
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
