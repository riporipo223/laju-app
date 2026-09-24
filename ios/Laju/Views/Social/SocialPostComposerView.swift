import SwiftUI

/// T4.15: the "Post pencapaian" entry point (user-flow.md §2.7) — reached from Run History, not the instant
/// post-run summary. `RunSummary`/`RunSummaryView` are purely local/offline, computed before the run has
/// even synced to the server, so there is no `serverRunId`/server status to gate posting on at that point.
/// Run History rows carry the server-confirmed `serverStatus` (T2.14/T2.14d), which is what the v1 AC
/// actually needs: "a run can only be posted once it's validated/approved" (phase-4-backlog.md T4.15 v1
/// scoping session, 2026-09-24).
struct SocialPostComposerView: View {
    let runId: String
    let onPosted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SocialViewModel()
    @State private var caption = ""
    @State private var isPosting = false

    private static let maxCaptionLength = 280

    var body: some View {
        NavigationStack {
            Form {
                Section("Caption (opsional)") {
                    TextField("Ceritain lari kamu...", text: $caption, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: caption) { newValue in
                            if newValue.count > Self.maxCaptionLength {
                                caption = String(newValue.prefix(Self.maxCaptionLength))
                            }
                        }
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(LajuColor.error)
                }
            }
            .navigationTitle("Post Pencapaian")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { post() }
                        .disabled(isPosting)
                }
            }
        }
    }

    private func post() {
        isPosting = true
        Task {
            let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let posted = await model.createPost(runId: runId, caption: trimmed.isEmpty ? nil : trimmed)
            isPosting = false
            if posted {
                onPosted()
                dismiss()
            }
        }
    }
}

#Preview {
    SocialPostComposerView(runId: "run-1", onPosted: {})
        .preferredColorScheme(.dark)
}
