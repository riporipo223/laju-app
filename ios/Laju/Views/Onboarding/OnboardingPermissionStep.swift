import SwiftUI

/// Context-then-prompt (user-flow.md §2.1) — explains WHY before the system dialog appears. Reuses the same
/// `LocationTrackingService.requestWhenInUseAuthorization()` `RunTrackingView` already calls; no new location
/// logic. Advances once the user has answered the system prompt, whichever way (T1.15 handles the
/// denied/When-In-Use/Always distinction on the tracking screen itself — this step is just the entry point).
struct OnboardingPermissionStep: View {
    @ObservedObject var locationService: LocationTrackingService
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "location.fill")
                .font(.system(size: 44))
                .foregroundStyle(LajuColor.background)
                .frame(width: 96, height: 96)
                .background(LajuColor.accent, in: Circle())

            Text("Izinkan akses lokasi")
                .font(LajuFont.heading)
                .foregroundStyle(LajuColor.textPrimary)
            Text("Laju pakai GPS buat catat jarak dan rute larimu — bahkan saat layar terkunci.")
                .font(LajuFont.body)
                .foregroundStyle(LajuColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()

            Button("Izinkan Akses Lokasi") {
                locationService.requestWhenInUseAuthorization()
            }
            .buttonStyle(.lajuPrimary)

            Button("Nanti saja", action: onFinished)
                .buttonStyle(.lajuSecondary)
        }
        .padding(24)
        .onChange(of: locationService.authorizationStatus) { _ in
            if locationService.authorizationStatus != .notDetermined {
                onFinished()
            }
        }
    }
}

#Preview {
    ZStack {
        LajuColor.background.ignoresSafeArea()
        OnboardingPermissionStep(locationService: LocationTrackingService(), onFinished: {})
    }
}
