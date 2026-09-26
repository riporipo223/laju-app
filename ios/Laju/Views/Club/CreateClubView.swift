import SwiftUI

/// T4.1: the Create Circle form, reached from `ClubHomeView`'s "Create Circle" button. Free for every
/// tier (product-spec.md §4.24 AC1) — a 2026-09-25 version of this screen Premium-gated it via a
/// `PremiumUpsellView`; that view and the gate it responded to are both gone, reverted 2026-09-26
/// (HANDOFF.md "Audit drift 2026-09-26" item 2).
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
            form
            .navigationTitle("Create Circle")
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
            Section("Nama Circle") {
                TextField("Nama circle...", text: $name)
            }
            Section("Deskripsi (opsional)") {
                TextField("Ceritain circle kamu...", text: $description, axis: .vertical)
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
            Button(model.isCreating ? "Membuat..." : "Buat Circle") { create() }
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
