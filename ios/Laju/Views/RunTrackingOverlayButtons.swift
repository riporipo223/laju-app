import SwiftUI

/// `RunTrackingView`'s floating top-right nav buttons (History, Profile) — extracted purely to keep
/// `RunTrackingView.swift` under SwiftLint's `file_length` limit, no behavioral difference from being inline.
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

    /// Entry point to the new Profile/Level screen (design-notes.md §5) — same floating-overlay pattern as
    /// `historyButton`, added alongside it since neither has a nav bar home anymore.
    var profileButton: some View {
        NavigationLink {
            ProfileView()
        } label: {
            Image(systemName: "person.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LajuColor.accent)
                .padding(10)
                .background(LajuColor.surface, in: Circle())
        }
    }
}
