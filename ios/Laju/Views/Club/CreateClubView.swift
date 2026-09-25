import SwiftUI

/// T4.1: the Create Club form, reached from `ClubHomeView`'s "Create Club" button. Premium-gated
/// server-side (`lib/club/premium.ts`) — a 403 `not_premium` swaps this form for `PremiumUpsellView`
/// instead of a generic error, since that is this task's expected, permanent state right now.
struct CreateClubView: View {
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CreateClubViewModel()
    @State private var name = ""
    @State private var description = ""
    @State private var privacy = "public"

    private static let privacies: [(value: String, label: String)] = [
        ("public", "Public"),
        ("invite_only", "Invite Only"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if model.isPremiumRequired {
                    ScrollView { PremiumUpsellView().padding() }
                } else {
                    form
                }
            }
            .navigationTitle("Create Club")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
        }
        .onChange(of: model.createdClub) { created in
            if created != nil {
                onCreated()
                dismiss()
            }
        }
    }

    private var form: some View {
        Form {
            Section("Nama Club") {
                TextField("Nama club...", text: $name)
            }
            Section("Deskripsi (opsional)") {
                TextField("Ceritain club kamu...", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("Privacy") {
                Picker("Privacy", selection: $privacy) {
                    ForEach(Self.privacies, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.segmented)
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(LajuColor.error)
            }
            Button(model.isCreating ? "Membuat..." : "Buat Club") { create() }
                .disabled(model.isCreating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func create() {
        Task {
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            await model.createClub(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                privacy: privacy
            )
        }
    }
}

#Preview {
    CreateClubView(onCreated: {})
        .preferredColorScheme(.dark)
}
