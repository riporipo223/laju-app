import SwiftUI

/// T3.9 (product-spec AC 4.7.2): season name and countdown, loaded from `GET /api/seasons/active`.
/// Past-season browsing is T3.8's neighbour screen, not built here (out of scope per the task).
struct SeasonInfoView: View {
    @StateObject private var viewModel = SeasonInfoViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.loadFailed, viewModel.season != nil {
                    Text("Gagal memperbarui — menampilkan data terakhir")
                        .font(.caption)
                        .foregroundStyle(LajuColor.warning)
                }

                if let season = viewModel.season {
                    // `.periodic(from:by:)` re-renders this subtree every minute so the countdown moves while
                    // the screen stays open, without a network call per tick (AC: "updates as time passes").
                    TimelineView(.periodic(from: season.startAt, by: 60)) { context in
                        SeasonInfoContent(
                            season: season,
                            daysRemaining: viewModel.liveDaysRemaining(now: context.date) ?? season.daysRemaining
                        )
                    }
                } else if viewModel.loadFailed {
                    failureState
                } else {
                    ProgressView()
                        .tint(LajuColor.accent)
                        .padding(.top, 80)
                }
            }
            .padding()
        }
        .background(LajuColor.background.ignoresSafeArea())
        .navigationTitle("Season")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var failureState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(LajuColor.textSecondary)
            Text("Tidak bisa memuat info season")
                .font(LajuFont.heading)
                .foregroundStyle(LajuColor.textPrimary)
            Text("Periksa koneksi dan pastikan kamu sudah masuk, lalu coba lagi.")
                .font(.subheadline)
                .foregroundStyle(LajuColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Coba lagi") { Task { await viewModel.load() } }
                .buttonStyle(LajuSecondaryButtonStyle())
        }
        .padding(.top, 60)
    }
}

/// Pure over its inputs (no view model, no clock of its own) — same shape as `LeaderboardContent` so it
/// renders identically in a test snapshot and on screen.
struct SeasonInfoContent: View {
    let season: ActiveSeasonResponse
    let daysRemaining: Int

    var body: some View {
        VStack(spacing: 16) {
            countdownCard
            if let me = season.me {
                mePositionCard(me)
            }
        }
    }

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            LajuLabelText(text: season.name)
            HStack(alignment: .firstTextBaseline) {
                Text("\(daysRemaining)")
                    .font(LajuFont.sectionNumber)
                    .foregroundStyle(LajuColor.accent)
                Text("hari lagi")
                    .font(LajuFont.heading)
                    .foregroundStyle(LajuColor.textPrimary)
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1)
                .fill(LajuColor.accent)
                .frame(height: 2)
                .padding(.horizontal, 24)
                .padding(.top, 1)
        }
    }

    private func mePositionCard(_ me: ActiveSeasonMe) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                LajuLabelText(text: "Poin season kamu")
                Text("\(me.seasonPoints) pts")
                    .font(LajuFont.heading)
                    .foregroundStyle(LajuColor.textPrimary)
            }
            Spacer()
            Text(me.league.capitalized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LajuColor.premium)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}
