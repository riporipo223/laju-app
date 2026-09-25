import SwiftUI

/// T4.16: a post's own screen — full post + flat comment list + input, reached by tapping the comment
/// icon on `SocialHomeView`'s feed card (phase-4-backlog.md T4.16 scoping session 2026-09-25: dedicated
/// detail screen, not an inline feed expansion — the feed's `SocialPostCard` stays lightweight).
struct SocialPostDetailView: View {
    let post: SocialPost

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CommentViewModel()
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        postSummary
                        Divider().overlay(LajuColor.hairline)
                        commentList
                    }
                    .padding()
                }
                composer
            }
            .background(LajuColor.background.ignoresSafeArea())
            .navigationTitle("Comment")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
            }
            .task { await model.load(postId: post.postId) }
        }
    }

    private var postSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(post.authorName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LajuColor.textPrimary)
            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(LajuFont.body)
                    .foregroundStyle(LajuColor.textPrimary)
            }
        }
    }

    @ViewBuilder
    private var commentList: some View {
        if model.isLoading, model.comments.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding()
        } else if model.comments.isEmpty {
            Text("Belum ada comment.")
                .font(.footnote)
                .foregroundStyle(LajuColor.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.comments) { comment in
                    commentRow(comment)
                }
            }
        }
    }

    private func commentRow(_ comment: SocialComment) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(comment.authorName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LajuColor.textPrimary)
                Text(comment.content)
                    .font(.subheadline)
                    .foregroundStyle(LajuColor.textPrimary)
            }
            Spacer()
            if model.isOwnComment(comment) {
                Button {
                    Task { await model.deleteComment(postId: post.postId, comment: comment) }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(LajuColor.textSecondary)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(LajuColor.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            HStack {
                TextField("Tulis comment...", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                Button("Kirim") { send() }
                    .disabled(model.isPosting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .background(LajuColor.surface)
    }

    private func send() {
        Task {
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if await model.postComment(postId: post.postId, content: trimmed) {
                draft = ""
            }
        }
    }
}

#Preview {
    SocialPostDetailView(
        post: SocialPost(
            postId: "post-1", userId: "usr-2", username: "budi_run", displayName: "Budi", avatarURL: nil,
            runId: "run-1", distanceMeters: 5230, durationSeconds: 1830, avgPaceSecPerKm: 350,
            finalPointsAwarded: 6, caption: "Lari pagi!", title: nil, description: nil, mapType: "standard",
            gearId: nil, createdAt: Date(), likeCount: 4, likedByCaller: false
        )
    )
    .preferredColorScheme(.dark)
}
