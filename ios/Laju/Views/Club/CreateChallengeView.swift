import SwiftUI

/// product-spec.md §4.24 AC13: create a Circle Challenge, reached from `ChallengeView`'s empty state
/// (owner/admin only — that check happens before this sheet is even presented, matching how
/// `ClubMemberListView`'s kick button only appears for `canKick`). Server-gated on Premium Club too —
/// a 403 `not_premium_club` swaps this form for `PremiumCircleUpsellView`.
struct CreateChallengeView: View {
    let clubId: String
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CreateChallengeViewModel()
    @State private var name = ""
    @State private var targetType = "distance"
    @State private var targetValueText = ""
    @State private var deadline = Date().addingTimeInterval(30 * 24 * 60 * 60)

    private static let targetTypes: [(value: String, label: String)] = [
        ("distance", "Jarak"),
        ("duration", "Durasi"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if model.isPremiumRequired {
                    ScrollView { PremiumCircleUpsellView().padding() }
                } else {
                    form
                }
            }
            .navigationTitle("Buat Challenge")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
        }
        .onChange(of: model.createdChallenge) { created in
            if created != nil {
                onCreated()
                dismiss()
            }
        }
    }

    private var form: some View {
        Form {
            Section("Nama Challenge") {
                TextField("mis. 500km bareng bulan ini", text: $name)
            }
            Section("Jenis Target") {
                Picker("Jenis Target", selection: $targetType) {
                    ForEach(Self.targetTypes, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section(targetType == "distance" ? "Target Jarak (km)" : "Target Durasi (jam)") {
                TextField(targetType == "distance" ? "mis. 500" : "mis. 50", text: $targetValueText)
                    .keyboardType(.decimalPad)
            }
            Section("Deadline") {
                DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                    .labelsHidden()
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(LajuColor.error)
            }
            Button(model.isCreating ? "Membuat..." : "Buat Challenge") { create() }
                .disabled(model.isCreating || !isValid)
        }
    }

    private var targetValueMeters: Double? {
        guard let raw = Double(targetValueText), raw > 0 else { return nil }
        // Distance entered in km (matches every other distance input in this app, e.g. leaderboard/run
        // summary display), converted to meters to match the backend's own unit convention. Duration
        // entered in hours, converted to seconds.
        return targetType == "distance" ? raw * 1000 : raw * 3600
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && targetValueMeters != nil && deadline > Date()
    }

    private func create() {
        guard let targetValue = targetValueMeters else { return }
        Task {
            await model.createChallenge(
                clubId: clubId,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                targetType: targetType,
                targetValue: targetValue,
                deadline: deadline
            )
        }
    }
}

#Preview {
    CreateChallengeView(clubId: "club-1", onCreated: {})
        .preferredColorScheme(.dark)
}
