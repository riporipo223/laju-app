import SwiftUI

/// `RunTrackingView`'s floating top-right nav button (History) — extracted purely to keep
/// `RunTrackingView.swift` under SwiftLint's `file_length` limit, no behavioral difference from being inline.
///
/// **2026-09-17 (T2.0a):** `profileButton` was removed from here. Profile is now the "You" tab in
/// `RootTabView`, so a floating overlay duplicating it on the Track screen was a second entry point to the
/// same destination. History stays an overlay push — it has no tab of its own and Profile only shows the 5
/// most recent runs, so this remains the only route to the full list.
extension RunTrackingView {
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
