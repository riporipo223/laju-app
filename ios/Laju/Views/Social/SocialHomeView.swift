import SwiftUI

/// Social tab root. **Replaced 2026-09-24** (was a placeholder since the 2026-09-24 nav restructure, Bagian
/// B item 6) — T4.15's v1 scope was closed the same day (phase-4-backlog.md: public feed, delete-own-post
/// moderation, no comments/report/block, a run must be `validated`/`approved` to post) and the backend
/// (`backend/app/api/social/posts/*`) is written against it. **Not functionally live yet**: the migration
/// creating `social_post`/`social_post_like` (`20260924220000_social_feed_schema.sql`) is written but NOT
/// applied to production — every call here fails until it is, the same situation `ClubHomeView` documents
/// for `ClubWarView`'s `not_premium_club` gate, except this one has no clean error code yet (a raw 500 from
/// the missing table), so `SocialViewModel.message(for:)` falls back to a generic "coba lagi" message for it.
/// Ungated (no `#if DEBUG`) on purpose, matching `ClubHomeView`'s reasoning: the backend is real code, not a
/// stub, so the UI is real code too — it just can't succeed against today's actual database.
struct SocialHomeView: View {
    @StateObject private var model: SocialViewModel
    private let loadsOnAppear: Bool
    /// T4.16: the post whose comments are showing — `.sheet(item:)`, not a `NavigationLink`, so the
    /// existing like/delete buttons inside `SocialPostCard` keep working without a tap-target conflict.
    @State private var selectedPostForComments: SocialPost?

    init(model: SocialViewModel = SocialViewModel(), loadsOnAppear: Bool = true) {
        _model = StateObject(wrappedValue: model)
        self.loadsOnAppear = loadsOnAppear
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.posts.isEmpty, !model.isLoading {
                    emptyState
                } else {
                    feedList
                }
            }
            .background(LajuColor.background.ignoresSafeArea())
            .navigationTitle("Social")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                if loadsOnAppear {
                    await model.load()
                }
            }
            .refreshable { await model.load() }
            .sheet(item: $selectedPostForComments) { post in
                SocialPostDetailView(post: post)
            }
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(LajuFont.body)
                        .foregroundStyle(LajuColor.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(model.posts) { post in
                    SocialPostCard(
                        post: post,
                        isOwnPost: model.isOwnPost(post),
                        onLikeToggle: { Task { await model.toggleLike(post) } },
                        onDelete: { Task { await model.deletePost(post) } },
                        onOpenComments: { selectedPostForComments = post }
                    )
                    .onAppear {
                        if post.id == model.posts.last?.id {
                            Task { await model.loadMore() }
                        }
                    }
                }

                if model.isLoadingMore {
                    ProgressView()
                        .padding()
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.largeTitle)
                .foregroundStyle(LajuColor.accent)
            Text("Belum ada post")
                .font(LajuFont.heading)
                .foregroundStyle(LajuColor.textPrimary)
            Text("Post pencapaian lari kamu dari Run History biar muncul di sini.")
                .font(.subheadline)
                .foregroundStyle(LajuColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LajuColor.background.ignoresSafeArea())
    }
}

private struct SocialPostCard: View {
    let post: SocialPost
    let isOwnPost: Bool
    let onLikeToggle: () -> Void
    let onDelete: () -> Void
    let onOpenComments: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if post.distanceMeters != nil {
                statRow
            }

            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(LajuFont.body)
                    .foregroundStyle(LajuColor.textPrimary)
            }

            likeRow
        }
        .padding(12)
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1)
                .fill(LajuColor.accent)
                .frame(height: 2)
                .padding(.horizontal, 16)
                .padding(.top, 1)
        }
        .alert("Hapus post ini?", isPresented: $showDeleteConfirmation) {
            Button("Batal", role: .cancel) {}
            Button("Hapus", role: .destructive, action: onDelete)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LajuColor.textPrimary)
                Text(post.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(LajuColor.textSecondary)
            }
            Spacer()
            if isOwnPost {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(LajuColor.textSecondary)
                }
            }
        }
    }

    /// `run` fields come from a live join (migration's own scope note) — all four are shown together, or
    /// none, never a partial row (checked once via `distanceMeters != nil` in the parent).
    private var statRow: some View {
        HStack {
            Text(DistanceFormatter.format(meters: post.distanceMeters ?? 0))
            Spacer()
            if let pace = post.avgPaceSecPerKm, (post.distanceMeters ?? 0) > 0 {
                Text(PaceFormatter.format(secPerKm: pace))
                Spacer()
            }
            if let points = post.finalPointsAwarded {
                Text(String(format: "%.0f pts", points))
                    .foregroundStyle(LajuColor.accent)
            }
        }
        .font(.subheadline)
        .foregroundStyle(LajuColor.textSecondary)
    }

    private var likeRow: some View {
        HStack(spacing: 16) {
            Button(action: onLikeToggle) {
                HStack(spacing: 4) {
                    Image(systemName: post.likedByCaller ? "heart.fill" : "heart")
                        .foregroundStyle(post.likedByCaller ? LajuColor.accent : LajuColor.textSecondary)
                    Text("\(post.likeCount)")
                        .font(.caption)
                        .foregroundStyle(LajuColor.textSecondary)
                }
            }
            /// T4.16: opens `SocialPostDetailView` — no comment count shown (the feed's own DTO doesn't
            /// carry one, v1 scope), just an entry point.
            Button(action: onOpenComments) {
                Image(systemName: "bubble.right")
                    .foregroundStyle(LajuColor.textSecondary)
            }
        }
        .padding(.top, 4)
    }
}

#Preview {
    SocialHomeView(
        model: SocialViewModel(
            previewPosts: [
                SocialPost(
                    postId: "post-1",
                    userId: "usr-2",
                    username: "budi_run",
                    displayName: "Budi",
                    avatarURL: nil,
                    runId: "run-1",
                    distanceMeters: 5230,
                    durationSeconds: 1830,
                    avgPaceSecPerKm: 350,
                    finalPointsAwarded: 6,
                    caption: "Lari pagi sebelum kerja!",
                    title: nil,
                    description: nil,
                    mapType: "standard",
                    gearId: nil,
                    createdAt: Date().addingTimeInterval(-3600),
                    likeCount: 4,
                    likedByCaller: false
                )
            ],
            currentUserId: "usr-1"
        ),
        loadsOnAppear: false
    )
    .preferredColorScheme(.dark)
}
