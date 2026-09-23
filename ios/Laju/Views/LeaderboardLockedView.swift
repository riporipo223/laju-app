import SwiftUI

/// The Leaderboard tab's locked state (product-spec.md §4.5 AC5, 2026-09-22). Shown instead of the board
/// when location permission has not been granted.
///
/// Copy and CTA follow the pattern `LocationPermissionBanner` already established for run tracking —
/// same "open Settings" affordance, same tone — rather than inventing a second permission vocabulary.
///
/// **Flagged as unconfirmed (product-spec.md §4.5 AC5 says so explicitly):** the locked-state fallback is
/// the PM's stated assumption, not a confirmed design, and AC5 does not distinguish `.notDetermined` from
/// `.denied` from `.restricted` at all. The three-way split here is this implementation's reading of it —
/// see `LeaderboardAccessState` for why each case behaves the way it does.
struct LeaderboardLockedView: View {
    let state: LeaderboardAccessState
    /// `nil` when there is nothing useful to ask for — `.denied` needs Settings, `.restricted` cannot be
    /// granted by the user at all.
    let onRequest: (() -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(LajuColor.textSecondary)

            Text(title)
                .font(LajuFont.heading)
                .foregroundStyle(LajuColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(LajuFont.body)
                .foregroundStyle(LajuColor.textSecondary)
                .multilineTextAlignment(.center)

            if let onRequest {
                Button("Izinkan lokasi", action: onRequest)
                    .buttonStyle(.lajuPrimary)
            } else if state == .denied {
                Button("Buka Pengaturan") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.lajuPrimary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LajuColor.background.ignoresSafeArea())
    }

    private var title: String {
        switch state {
        case .unlocked: ""
        case .needsPermission: "Papan peringkat butuh izin lokasi"
        case .denied: "Izin lokasi ditolak"
        case .restricted: "Izin lokasi dibatasi perangkat"
        }
    }

    private var message: String {
        switch state {
        case .unlocked:
            ""
        case .needsPermission:
            "Aktifkan izin lokasi untuk melihat papan peringkat. Lari, poin, dan level tetap berjalan tanpa ini."
        case .denied:
            "Aktifkan izin lokasi lewat Pengaturan untuk melihat papan peringkat. "
                + "Lari, poin, dan level tetap berjalan tanpa ini."
        case .restricted:
            "Perangkat ini membatasi izin lokasi (mis. kontrol orang tua), jadi papan peringkat tidak bisa dibuka. "
                + "Lari, poin, dan level tetap berjalan seperti biasa."
        }
    }
}
