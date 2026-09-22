import SwiftUI

/// T2.20: global leaderboard screen — product-spec.md §4.5. Top N from the precomputed board plus the
/// caller's own position even when outside that window (AC 4.5.1), with the board's age stated (AC 4.5.2).
/// Region filters are Fase 3 (T3.4/T3.5).
struct LeaderboardView: View {
    @StateObject private var viewModel = LeaderboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.loadFailed, viewModel.response != nil {
                    Text("Gagal memperbarui — menampilkan data terakhir")
                        .font(.caption)
                        .foregroundStyle(LajuColor.warning)
                }

                if let response = viewModel.response {
                    LeaderboardContent(response: response, now: Date())
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
        .navigationTitle("Leaderboard")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // T3.9: only reachable entry point for the season info screen — no tab of its own (RootTabView.swift).
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    SeasonInfoView()
                } label: {
                    Image(systemName: "calendar")
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var failureState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(LajuColor.textSecondary)
            Text("Tidak bisa memuat leaderboard")
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

/// The loaded board — pure over its inputs (no view model, no clock of its own) so it renders identically in
/// a test snapshot and on screen.
struct LeaderboardContent: View {
    let response: LeaderboardResponse
    let now: Date

    var body: some View {
        VStack(spacing: 16) {
            myPositionCard

            Text(LeaderboardFreshness.text(computedAt: response.computedAt, now: now))
                .font(.caption)
                .foregroundStyle(
                    LeaderboardFreshness.isStale(computedAt: response.computedAt, now: now)
                        ? LajuColor.warning : LajuColor.textSecondary
                )
                .frame(maxWidth: .infinity, alignment: .leading)

            if response.entries.isEmpty {
                Text("Belum ada pelari di leaderboard musim ini.")
                    .font(.subheadline)
                    .foregroundStyle(LajuColor.textSecondary)
                    .padding(.top, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(response.entries) { entry in
                        entryRow(entry)
                        if entry.id != response.entries.last?.id {
                            Divider().overlay(LajuColor.hairline)
                        }
                    }
                }
                .padding(.horizontal)
                .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private var myPositionCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            LajuLabelText(text: "Posisi kamu")
            if let me = response.me {
                HStack(alignment: .firstTextBaseline) {
                    Text("#\(me.rank)")
                        .font(LajuFont.sectionNumber)
                        .foregroundStyle(LajuColor.accent)
                    Spacer()
                    Text("\(me.points) pts")
                        .font(LajuFont.heading)
                        .foregroundStyle(LajuColor.textPrimary)
                }
            } else {
                Text("Belum masuk leaderboard — selesaikan run untuk mendapat poin.")
                    .font(.subheadline)
                    .foregroundStyle(LajuColor.textSecondary)
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

    private func entryRow(_ entry: LeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(LajuFont.heading)
                .foregroundStyle(entry.rank <= 3 ? LajuColor.accent : LajuColor.textSecondary)
                .frame(width: 44, alignment: .leading)
            Text(entry.username ?? "Pelari tanpa nama")
                .font(LajuFont.body)
                .foregroundStyle(LajuColor.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("\(entry.points) pts")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LajuColor.textSecondary)
        }
        .padding(.vertical, 12)
    }
}
