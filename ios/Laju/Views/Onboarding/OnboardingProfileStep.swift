import SwiftUI

/// The step between sign-in and the location prompt: a username and the three region fields (product-spec.md §4.1 AC2,
/// decision D1 — region stays mandatory in v1). It is what finally makes the app call `POST /api/profile/complete`.
/// Region is free text until the cascading picker exists (see `ProfileSetupViewModel`).
struct OnboardingProfileStep: View {
    @StateObject private var model: ProfileSetupViewModel
    let onContinue: () -> Void

    init(accessToken: @escaping @Sendable () async throws -> String, onContinue: @escaping () -> Void) {
        _model = StateObject(wrappedValue: ProfileSetupViewModel(accessToken: accessToken))
        self.onContinue = onContinue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Satu langkah lagi")
                    .font(LajuFont.heading)
                    .foregroundStyle(LajuColor.textPrimary)
                    .padding(.top, 48)
                Text(
                    "Pilih nama panggilan dan wilayahmu. Wilayah dipakai untuk peringkat regional nanti."
                )
                .font(LajuFont.body)
                .foregroundStyle(LajuColor.textSecondary)

                field("Nama panggilan", text: $model.username, caps: .never)
                Text("3–24 karakter: huruf, angka, atau garis bawah.")
                    .font(.footnote)
                    .foregroundStyle(LajuColor.textSecondary)
                field("Kecamatan", text: $model.kecamatan, caps: .words)
                field("Kabupaten / Kota", text: $model.kabupatenKota, caps: .words)
                field("Provinsi", text: $model.provinsi, caps: .words)

                if case let .failed(message) = model.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(LajuColor.error)
                }

                Button {
                    Task {
                        if await model.submit() {
                            onContinue()
                        }
                    }
                } label: {
                    if model.state == .submitting {
                        ProgressView().tint(LajuColor.background)
                    } else {
                        Text("Simpan")
                    }
                }
                .buttonStyle(.lajuPrimary)
                .disabled(!model.canSubmit)
                .opacity(model.canSubmit ? 1 : 0.5)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field(_ title: String, text: Binding<String>, caps: TextInputAutocapitalization) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(caps)
            .autocorrectionDisabled()
            .font(LajuFont.body)
            .foregroundStyle(LajuColor.textPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(LajuColor.hairline, lineWidth: 1))
    }
}
