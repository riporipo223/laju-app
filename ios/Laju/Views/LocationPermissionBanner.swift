import CoreLocation
import SwiftUI
import UIKit

/// T1.15: distinct copy per authorization state (product-spec.md §4.15) — the prior flow only distinguished
/// Always vs Denied, silently treating While Using as "fine". `.authorizedAlways` needs no notice (ideal
/// state, `nil`); `.notDetermined` also renders nothing here — the system permission prompt itself is the
/// notice at that moment (`RunTrackingView`'s own `.onAppear` request flow), not a persistent banner.
enum LocationPermissionNotice: Equatable {
    case whileUsingOnly
    case denied

    static func notice(for status: CLAuthorizationStatus) -> LocationPermissionNotice? {
        switch status {
        case .authorizedWhenInUse: .whileUsingOnly
        case .denied, .restricted: .denied
        default: nil
        }
    }

    var title: String {
        switch self {
        case .whileUsingOnly: "Lokasi hanya aktif saat app dibuka"
        case .denied: "Izin lokasi ditolak"
        }
    }

    /// While Using AC (product-spec §4.15): must explicitly warn that an active run can stop tracking if the
    /// app is backgrounded — not something the user discovers mid-run on their own.
    var message: String {
        switch self {
        case .whileUsingOnly:
            "Tracking berhenti kalau kamu kunci layar atau pindah app saat run aktif. " +
                "Upgrade ke \"Always\" di Pengaturan supaya run tetap tercatat di background."
        case .denied:
            "Laju butuh akses lokasi untuk melacak jarak dan rute run kamu. Aktifkan lewat Pengaturan."
        }
    }
}

/// Settings deep link (AC: reachable without reinstall) — `UIApplication.openSettingsURLString` opens Laju's
/// own Settings page directly, not the general Settings root.
struct LocationPermissionBanner: View {
    let notice: LocationPermissionNotice
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(notice.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LajuColor.textPrimary)
            Text(notice.message)
                .font(.caption)
                .foregroundStyle(LajuColor.textSecondary)
            Button("Buka Pengaturan") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(LajuColor.accent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1)
                .fill(LajuColor.warning)
                .frame(height: 2)
                .padding(.horizontal, 16)
                .padding(.top, 1)
        }
    }
}
