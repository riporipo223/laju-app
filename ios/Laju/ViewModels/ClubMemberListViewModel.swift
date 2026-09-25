import Foundation

/// T4.1b: a club's member list + self-leave. `currentUserId` (via `fetchCurrentUserId`, same pattern
/// `SocialViewModel` uses) is how the view knows to show a "Leave Club" button for the caller's own row.
@MainActor
final class ClubMemberListViewModel: ObservableObject {
    @Published private(set) var members: [ClubMember] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLeaving = false
    @Published private(set) var currentUserId: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var didLeave = false

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

    func isCurrentUser(_ member: ClubMember) -> Bool {
        currentUserId != nil && member.userId == currentUserId
    }

    func load(clubId: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let jwt = try await currentJWT()
            if currentUserId == nil {
                currentUserId = try? await apiClient.fetchCurrentUserId(jwt: jwt)
            }
            members = try await apiClient.fetchClubMembers(clubId: clubId, jwt: jwt).members
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func leave(clubId: String) async {
        guard !isLeaving else { return }
        isLeaving = true
        defer { isLeaving = false }
        do {
            let jwt = try await currentJWT()
            _ = try await apiClient.leaveClub(clubId: clubId, jwt: jwt)
            didLeave = true
            members.removeAll { isCurrentUser($0) }
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        if error is URLError {
            return "Tidak ada koneksi. Coba lagi saat online."
        }
        return "Member list belum bisa dimuat. Coba lagi."
    }

    #if DEBUG
        /// MOCK: preview-only state, never used by the app's real code paths.
        init(previewMembers: [ClubMember], currentUserId: String?) {
            apiClient = APIClient()
            currentJWT = { "preview" }
            members = previewMembers
            self.currentUserId = currentUserId
        }
    #endif
}
