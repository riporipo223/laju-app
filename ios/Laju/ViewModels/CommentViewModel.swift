import Foundation

/// T4.16: comment state for a single post's detail screen — flat list, no nested replies (v1 scope,
/// phase-4-backlog.md T4.16 scoping session 2026-09-25). Same DI shape `SocialViewModel`/`GearViewModel`
/// already use.
@MainActor
final class CommentViewModel: ObservableObject {
    @Published private(set) var comments: [SocialComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPosting = false
    @Published private(set) var currentUserId: String?
    @Published private(set) var errorMessage: String?

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

    func isOwnComment(_ comment: SocialComment) -> Bool {
        currentUserId != nil && comment.userId == currentUserId
    }

    func load(postId: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let jwt = try await currentJWT()
            if currentUserId == nil {
                currentUserId = try? await apiClient.fetchCurrentUserId(jwt: jwt)
            }
            comments = try await apiClient.fetchComments(postId: postId, jwt: jwt).comments
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// - Returns: `true` once the server accepted the comment. Appends the server-returned row (real id,
    /// no synthetic local row) rather than reloading the whole list.
    @discardableResult
    func postComment(postId: String, content: String) async -> Bool {
        guard !isPosting else { return false }
        isPosting = true
        defer { isPosting = false }
        do {
            let jwt = try await currentJWT()
            let comment = try await apiClient.createComment(postId: postId, content: content, jwt: jwt)
            comments.append(comment)
            errorMessage = nil
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Optimistic remove — restored if the server call fails, same pattern `SocialViewModel.deletePost`
    /// already uses.
    func deleteComment(postId: String, comment: SocialComment) async {
        let previous = comments
        comments.removeAll { $0.id == comment.id }
        do {
            let jwt = try await currentJWT()
            _ = try await apiClient.deleteComment(postId: postId, commentId: comment.commentId, jwt: jwt)
        } catch {
            comments = previous
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        if error is URLError {
            return "Tidak ada koneksi. Coba lagi saat online."
        }
        guard case let APIClientError.server(_, body) = error else {
            return "Comment belum bisa dimuat. Coba lagi."
        }
        let lowered = body.lowercased()
        if lowered.contains("at most 280") {
            return "Comment kemaksimal 280 karakter."
        }
        if lowered.contains("content is required") {
            return "Comment tidak boleh kosong."
        }
        return "Comment belum bisa dimuat. Coba lagi."
    }

    #if DEBUG
        /// MOCK: preview-only state, never used by the app's real code paths.
        init(previewComments: [SocialComment], currentUserId: String?) {
            apiClient = APIClient()
            currentJWT = { "preview" }
            comments = previewComments
            self.currentUserId = currentUserId
        }
    #endif
}
