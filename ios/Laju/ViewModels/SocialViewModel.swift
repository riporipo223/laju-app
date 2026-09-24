import Foundation

/// T4.15: state for the Social Feed screen (v1 scope, phase-4-backlog.md — public feed, delete-own-post
/// moderation, no comments/report/block). The backend is written but its migration isn't applied yet
/// (`20260924220000_social_feed_schema.sql`) — see `SocialDTOs.swift`'s header comment — so `load()` fails
/// against the live database until it is, same situation `ClubWarViewModel` documented for T4.2c.
@MainActor
final class SocialViewModel: ObservableObject {
    @Published private(set) var posts: [SocialPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentUserId: String?

    private let apiClient: APIClient
    private let currentJWT: @Sendable () async throws -> String

    init(
        apiClient: APIClient = APIClient(),
        currentJWT: @escaping @Sendable () async throws -> String = {
            try await SupabaseConfig.client.auth.session.accessToken
        }
    ) {
        self.apiClient = apiClient
        self.currentJWT = currentJWT
    }

    func isOwnPost(_ post: SocialPost) -> Bool {
        currentUserId != nil && post.userId == currentUserId
    }

    /// Fresh newest-first page — first appearance and pull-to-refresh both call this, never `loadMore`.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let jwt = try await currentJWT()
            // Best-effort: a failure here still lets the feed itself load, just without delete-own-post shown.
            if currentUserId == nil {
                currentUserId = try? await apiClient.fetchCurrentUserId(jwt: jwt)
            }
            let page = try await apiClient.fetchSocialFeed(before: nil, limit: nil, jwt: jwt)
            posts = page.posts
            hasMore = page.hasMore
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Older posts appended past the current last row (infinite scroll) — cursor is the last-loaded row's
    /// `createdAt`, matching the server's own `next_before` semantics.
    func loadMore() async {
        guard hasMore, !isLoadingMore, let cursor = posts.last?.createdAt else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let jwt = try await currentJWT()
            let page = try await apiClient.fetchSocialFeed(before: cursor, limit: nil, jwt: jwt)
            posts.append(contentsOf: page.posts)
            hasMore = page.hasMore
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// - Returns: `true` once the server accepted the post. Reloads the feed on success so the new post's
    /// real server-assigned id/author fields appear, rather than constructing a synthetic row locally.
    func createPost(runId: String, caption: String?) async -> Bool {
        do {
            let jwt = try await currentJWT()
            _ = try await apiClient.createSocialPost(runId: runId, caption: caption, jwt: jwt)
            await load()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Optimistic remove — restored if the server call fails, so a flaky network doesn't silently desync
    /// the list from what's actually still on the server.
    func deletePost(_ post: SocialPost) async {
        let previous = posts
        posts.removeAll { $0.id == post.id }
        do {
            let jwt = try await currentJWT()
            _ = try await apiClient.deleteSocialPost(postId: post.postId, jwt: jwt)
        } catch {
            posts = previous
            errorMessage = Self.message(for: error)
        }
    }

    /// Optimistic toggle — flips immediately, then reconciles with the server's own authoritative count;
    /// reverts to the pre-toggle state on failure rather than leaving a like the server never recorded.
    func toggleLike(_ post: SocialPost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let before = posts[index]
        let optimisticLiked = !before.likedByCaller
        posts[index].likedByCaller = optimisticLiked
        posts[index].likeCount = max(0, before.likeCount + (optimisticLiked ? 1 : -1))

        do {
            let jwt = try await currentJWT()
            let response = optimisticLiked
                ? try await apiClient.likeSocialPost(postId: post.postId, jwt: jwt)
                : try await apiClient.unlikeSocialPost(postId: post.postId, jwt: jwt)
            if let current = posts.firstIndex(where: { $0.id == post.id }) {
                posts[current].likedByCaller = response.liked
                posts[current].likeCount = response.likeCount
            }
        } catch {
            if let current = posts.firstIndex(where: { $0.id == post.id }) {
                posts[current] = before
            }
            errorMessage = Self.message(for: error)
        }
    }

    private static let errorMessages: [String: String] = [
        "run not found": "Lari itu tidak ditemukan.",
        "you can only post your own runs": "Kamu cuma bisa post lari kamu sendiri.",
        "only a validated or approved run can be posted": "Lari ini belum bisa diposting — tunggu sampai statusnya valid.",
        "caption may be at most": "Caption kemaksimal 280 karakter."
    ]

    static func message(for error: Error) -> String {
        if error is URLError {
            return "Tidak ada koneksi. Coba lagi saat online."
        }
        guard case let APIClientError.server(_, body) = error else {
            return "Feed belum bisa dimuat. Coba lagi."
        }
        let lowered = body.lowercased()
        let match = errorMessages.first { lowered.contains($0.key) }
        return match?.value ?? "Feed belum bisa dimuat. Coba lagi."
    }

    #if DEBUG
        /// MOCK: preview-only state, never used by the app's real code paths.
        init(previewPosts: [SocialPost], currentUserId: String?) {
            apiClient = APIClient()
            currentJWT = { "preview" }
            posts = previewPosts
            self.currentUserId = currentUserId
        }

        /// Test-only: seeds `posts` directly (e.g. `StubURLProtocol`-backed unit tests exercising
        /// `toggleLike`/`deletePost`'s optimistic-update behavior) without a real `load()` round-trip.
        func seedForTest(posts: [SocialPost]) {
            self.posts = posts
        }
    #endif
}
