import SwiftUI

/// product-spec.md §4.24 AC13: a Circle's challenge — visible to every current member (not just
/// owner/admin, unlike Circle analytics), progress + individual ranking. Owner-only Cancel button,
/// gated by `ChallengeViewModel.isOwner` (reused from the same member-role lookup
/// `ClubMemberListView`'s kick button already established).
struct ChallengeView: View {
    let clubId: String

    @StateObject private var model = ChallengeViewModel()
    @State private var showingCreateChallenge = false
    @State private var showingCancelConfirmation = false

    var body: some View {
        Group {
            if let challenge = model.challenge {
                content(for: challenge)
            } else if model.hasNoChallenge {
                emptyState
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(LajuColor.error)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Challenge")
        .task { await model.load(clubId: clubId) }
        .refreshable { await model.load(clubId: clubId) }
        .sheet(isPresented: $showingCreateChallenge) {
            CreateChallengeView(clubId: clubId) {
                Task { await model.load(clubId: clubId) }
            }
        }
        .alert("Batalkan Challenge?", isPresented: $showingCancelConfirmation) {
            Button("Batalkan", role: .destructive) {
                Task { await model.cancel(clubId: clubId) }
            }
            Button("Tidak", role: .cancel) {}
        } message: {
            Text("Ranking yang sudah ada akan dibekukan sebagai rekam final, bukan dihapus. Aksi ini tidak bisa dibatalkan.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.largeTitle)
                .foregroundStyle(LajuColor.textSecondary)
            Text("Belum ada challenge")
                .font(LajuFont.heading)
                .foregroundStyle(LajuColor.textPrimary)
            Text("Circle ini belum punya challenge yang berjalan.")
                .font(LajuFont.body)
                .foregroundStyle(LajuColor.textSecondary)
                .multilineTextAlignment(.center)
            if model.isOwner {
                Button("Buat Challenge") { showingCreateChallenge = true }
                    .buttonStyle(.lajuPrimary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(for challenge: ChallengeProgressResponse) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(challenge.name)
                        .font(LajuFont.heading)
                        .foregroundStyle(LajuColor.textPrimary)
                    Text(statusLabel(challenge.status))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(statusColor(challenge.status))
                    Text("\(formattedValue(challenge.collectiveTotal, type: challenge.targetType)) / \(formattedValue(challenge.targetValue, type: challenge.targetType))")
                        .font(LajuFont.body)
                        .foregroundStyle(LajuColor.textSecondary)
                }
                .padding(.vertical, 4)
            }

            Section("Ranking") {
                if challenge.ranking.isEmpty {
                    Text("Belum ada kontribusi.")
                        .foregroundStyle(LajuColor.textSecondary)
                } else {
                    ForEach(Array(challenge.ranking.enumerated()), id: \.element.id) { index, entry in
                        HStack {
                            Text("\(index + 1).")
                                .foregroundStyle(LajuColor.textSecondary)
                            Text(entry.userId)
                                .foregroundStyle(LajuColor.textPrimary)
                            Spacer()
                            Text(formattedValue(entry.total, type: challenge.targetType))
                                .foregroundStyle(LajuColor.textSecondary)
                        }
                    }
                }
            }

            if model.isOwner, challenge.status == "active" || challenge.status == "target_reached" {
                Section {
                    Button("Batalkan Challenge", role: .destructive) {
                        showingCancelConfirmation = true
                    }
                    .disabled(model.isCancelling)
                }
            }

            if model.didCancel {
                Section {
                    Text("Challenge dibekukan sebagai rekam final. Ranking di atas tetap tersimpan.")
                        .font(.footnote)
                        .foregroundStyle(LajuColor.textSecondary)
                }
            }
        }
    }

    private func formattedValue(_ value: Double, type: String) -> String {
        type == "distance" ? DistanceFormatter.format(meters: value) : DurationFormatter.format(seconds: value)
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "active": "Berjalan"
        case "target_reached": "Target tercapai"
        case "closed_success": "Selesai — berhasil"
        case "closed_missed": "Selesai — tidak tercapai"
        case "cancelled": "Dibatalkan"
        default: status
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active", "target_reached": LajuColor.accent
        case "closed_success": LajuColor.accent
        case "closed_missed", "cancelled": LajuColor.textSecondary
        default: LajuColor.textSecondary
        }
    }
}

#Preview {
    NavigationStack {
        ChallengeView(clubId: "club-1")
    }
    .preferredColorScheme(.dark)
}
