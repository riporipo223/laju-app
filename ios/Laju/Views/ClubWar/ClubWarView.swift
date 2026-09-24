import SwiftUI

#if DEBUG
    /// T4.2c scaffold (product-spec.md §4.19): record, active war with its 48h countdown, incoming challenges to
    /// accept/decline, outgoing challenges, and sending a new one. DEBUG-only until it can actually work —
    /// T4.2a's migration isn't applied and the Premium check always denies until T4.20. Club names and the
    /// challengeable-club list come from `ClubWarPreviewData` (MOCK).
    struct ClubWarView: View {
        @StateObject private var model: ClubWarViewModel
        @State private var showChallengeSheet = false
        private let loadsOnAppear: Bool

        init(model: ClubWarViewModel = ClubWarViewModel(), loadsOnAppear: Bool = true) {
            _model = StateObject(wrappedValue: model)
            self.loadsOnAppear = loadsOnAppear
        }

        var body: some View {
            ScrollView {
                VStack(spacing: 24) {
                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(LajuFont.body)
                            .foregroundStyle(LajuColor.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    recordSection
                    activeWarSection
                    incomingSection
                    outgoingSection
                    Button("Tantang club lain") { showChallengeSheet = true }
                        .buttonStyle(.lajuPrimary)
                }
                .padding()
            }
            .background(LajuColor.background.ignoresSafeArea())
            .navigationTitle("Club War")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                if loadsOnAppear {
                    await model.load()
                }
            }
            .refreshable { await model.load() }
            .sheet(isPresented: $showChallengeSheet) {
                ClubWarChallengeSheet(ownClubId: model.myClubId) { clubIds in
                    await model.sendChallenge(to: clubIds)
                }
            }
        }

        private var recordSection: some View {
            card(title: "Club War Record") {
                HStack(spacing: 24) {
                    stat(value: model.record?.wins, label: "Menang")
                    stat(value: model.record?.losses, label: "Kalah")
                    stat(value: model.record?.netWins, label: "Net")
                }
            }
        }

        @ViewBuilder
        private var activeWarSection: some View {
            if let war = model.activeWar, let endsAt = war.endsAt {
                card(title: "War berjalan") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = ClubWarViewModel.secondsRemaining(until: endsAt, now: context.date)
                        Text(ClubWarViewModel.countdownText(seconds: seconds))
                            .font(LajuFont.sectionNumber)
                            .monospacedDigit()
                            .foregroundStyle(LajuColor.accent)
                    }
                    clubsLine(war)
                }
            }
        }

        @ViewBuilder
        private var incomingSection: some View {
            if !model.incomingChallenges.isEmpty {
                card(title: "Tantangan masuk") {
                    ForEach(model.incomingChallenges) { war in
                        VStack(alignment: .leading, spacing: 8) {
                            clubsLine(war)
                            HStack {
                                Button("Terima") { Task { await model.respond(to: war.id, accept: true) } }
                                    .buttonStyle(.lajuPrimary)
                                Button("Tolak") { Task { await model.respond(to: war.id, accept: false) } }
                                    .buttonStyle(.lajuSecondary)
                            }
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private var outgoingSection: some View {
            if !model.outgoingChallenges.isEmpty {
                card(title: "Menunggu jawaban") {
                    ForEach(model.outgoingChallenges) { war in
                        clubsLine(war)
                    }
                }
            }
        }

        private func clubsLine(_ war: ClubWar) -> some View {
            Text(war.clubs.map { ClubWarPreviewData.displayName(for: $0.clubId) }.joined(separator: " vs "))
                .font(LajuFont.body)
                .foregroundStyle(LajuColor.textSecondary)
        }

        private func stat(value: Int?, label: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(value.map(String.init) ?? "–")
                    .font(LajuFont.sectionNumber)
                    .foregroundStyle(LajuColor.textPrimary)
                Text(label)
                    .font(LajuFont.label)
                    .foregroundStyle(LajuColor.textSecondary)
            }
        }

        private func card(title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(LajuFont.heading)
                    .foregroundStyle(LajuColor.textPrimary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    /// Picks 1–2 other clubs to challenge (§4.19 AC1). The club list is MOCK — no browse endpoint until T4.1b.
    struct ClubWarChallengeSheet: View {
        let ownClubId: String?
        let onSend: @MainActor ([String]) async -> Bool

        @Environment(\.dismiss) private var dismiss
        @State private var selected: Set<String> = []
        @State private var isSending = false

        private static let maxInvited = 2

        var body: some View {
            NavigationStack {
                List(candidates) { club in
                    Button {
                        toggle(club.id)
                    } label: {
                        HStack {
                            Text(club.name)
                            Spacer()
                            if selected.contains(club.id) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!selected.contains(club.id) && selected.count >= Self.maxInvited)
                }
                .navigationTitle("Tantang club")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Batal") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kirim") { send() }
                            .disabled(selected.isEmpty || isSending)
                    }
                }
            }
        }

        private var candidates: [ClubWarPreviewData.ClubOption] {
            ClubWarPreviewData.challengeableClubs.filter { $0.id != ownClubId }
        }

        private func toggle(_ clubId: String) {
            if selected.contains(clubId) {
                selected.remove(clubId)
            } else if selected.count < Self.maxInvited {
                selected.insert(clubId)
            }
        }

        private func send() {
            isSending = true
            Task {
                let sent = await onSend(Array(selected))
                isSending = false
                if sent {
                    dismiss()
                }
            }
        }
    }

    #Preview("Club War — MOCK data") {
        NavigationStack {
            ClubWarView(model: ClubWarPreviewData.viewModel(), loadsOnAppear: false)
        }
    }
#endif
