import Foundation

/// T4.1b: browse + join state — same DI shape every other social/club view model uses.
@MainActor
final class ClubBrowseViewModel: ObservableObject {
    @Published private(set) var clubs: [ClubSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?
    /// `true` when a join attempt needs an invite code the caller hasn't supplied (or supplied wrong) —
    /// its own state, not folded into `errorMessage`, so the view can prompt for a code specifically.
    @Published private(set) var invitePromptClubId: String?

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

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let jwt = try await currentJWT()
            let page = try await apiClient.browseClubs(before: nil, limit: nil, jwt: jwt)
            clubs = page.clubs
            hasMore = page.hasMore
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, let cursor = clubs.last?.createdAt else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let jwt = try await currentJWT()
            let page = try await apiClient.browseClubs(before: cursor, limit: nil, jwt: jwt)
            clubs.append(contentsOf: page.clubs)
            hasMore = page.hasMore
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// - Returns: `true` once joined. Sets `invitePromptClubId` (not `errorMessage`) when the club needs
    /// an invite code that wasn't given or didn't match, so the view can ask for one specifically.
    @discardableResult
    func joinClub(_ club: ClubSummary, inviteCode: String?) async -> Bool {
        do {
            let jwt = try await currentJWT()
            _ = try await apiClient.joinClub(clubId: club.clubId, inviteCode: inviteCode, jwt: jwt)
            invitePromptClubId = nil
            errorMessage = nil
            return true
        } catch let APIClientError.server(statusCode, _) where statusCode == 403 && club.privacy == "invite_only" {
            invitePromptClubId = club.clubId
            return false
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    private static func message(for error: Error) -> String {
        if error is URLError {
            return "Tidak ada koneksi. Coba lagi saat online."
        }
        guard case let APIClientError.server(_, body) = error else {
            return "Club belum bisa dimuat. Coba lagi."
        }
        if body.lowercased().contains("already in a club") {
            return "Kamu sudah tergabung di club lain."
        }
        return "Club belum bisa dimuat. Coba lagi."
    }

    #if DEBUG
        /// MOCK: preview-only state, never used by the app's real code paths.
        init(previewClubs: [ClubSummary]) {
            apiClient = APIClient()
            currentJWT = { "preview" }
            clubs = previewClubs
        }
    #endif
}
