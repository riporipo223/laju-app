import SwiftUI

/// Explains the core loop (Track → Earn Points → Level Up, user-flow.md §2.2) visually before asking for any
/// permission — so the location prompt that follows has context, not just a bare system dialog.
struct OnboardingCoreLoopStep: View {
    let onContinue: () -> Void

    private struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    private let items: [Item] = [
        Item(icon: "location.fill", title: "Track", body: "GPS otomatis catat jarak, pace, dan rutemu."),
        Item(
            icon: "star.fill",
            title: "Earn Points",
            body: "Tiap lari dapat poin — makin jauh & konsisten, makin banyak."
        ),
        Item(icon: "arrow.up.circle.fill", title: "Level Up", body: "Kumpulkan poin, naik level, buka pencapaian baru.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Spacer()
            ForEach(items) { item in
                HStack(spacing: 16) {
                    Image(systemName: item.icon)
                        .font(.title2)
                        .foregroundStyle(LajuColor.accent)
                        .frame(width: 48, height: 48)
                        .background(LajuColor.surface, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(LajuFont.heading)
                            .foregroundStyle(LajuColor.textPrimary)
                        Text(item.body)
                            .font(LajuFont.body)
                            .foregroundStyle(LajuColor.textSecondary)
                    }
                }
            }
            Spacer()
            Spacer()
            Button("Lanjutkan", action: onContinue)
                .buttonStyle(.lajuPrimary)
        }
        .padding(24)
    }
}

#Preview {
    OnboardingCoreLoopStep(onContinue: {})
}
