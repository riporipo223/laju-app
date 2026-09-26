import Foundation

/// product-spec.md §4.24 AC13: a Circle's challenge — progress, ranking, empty state, owner-only
/// cancel. `isOwner` is derived from the same `fetchClubMembers`/`fetchCurrentUserId` pair
/// `ClubMemberListViewModel` uses for `isCurrentUser`/`canKick` — reused, not a new lookup mechanism.
@MainActor
final class ChallengeViewModel: ObservableObject {
    @Published private(set) var challenge: ChallengeProgressResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var isCancelling = false
    @Published private(set) var hasNoChallenge = false
    @Published private(set) var isOwner = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var didCancel = false

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

    func load(clubId: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        hasNoChallenge = false
        defer { isLoading = false }
        do {
            let jwt = try await currentJWT()
            if let currentUserId = try? await apiClient.fetchCurrentUserId(jwt: jwt) {
                let members = try? await apiClient.fetchClubMembers(clubId: clubId, jwt: jwt)
                isOwner = members?.members.first { $0.userId == currentUserId }?.role == "owner"
            }
            challenge = try await apiClient.fetchChallenge(clubId: clubId, jwt: jwt)
        } catch let APIClientError.server(statusCode, _) where statusCode == 404 {
            challenge = nil
            hasNoChallenge = true
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func cancel(clubId: String) async {
        guard !isCancelling, challenge != nil else { return }
        isCancelling = true
        errorMessage = nil
        defer { isCancelling = false }
        do {
            let jwt = try await currentJWT()
            _ = try await apiClient.cancelChallenge(clubId: clubId, jwt: jwt)
            didCancel = true
            await load(clubId: clubId)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        if error is URLError {
            return "Tidak ada koneksi. Coba lagi saat online."
        }
        return "Challenge belum bisa dimuat. Coba lagi."
    }

    #if DEBUG
        /// MOCK: preview-only state, never used by the app's real code paths.
        init(previewChallenge: ChallengeProgressResponse?, isOwner: Bool) {
            apiClient = APIClient()
            currentJWT = { "preview" }
            challenge = previewChallenge
            hasNoChallenge = previewChallenge == nil
            self.isOwner = isOwner
        }
    #endif
}
