import Foundation

/// T4.1b: a club's member list + self-leave + kick-member (product-spec.md §4.24 AC23, added
/// 2026-09-26). `currentUserId` (via `fetchCurrentUserId`, same pattern `SocialViewModel` uses) is how
/// the view knows to show a "Leave" button for the caller's own row, and `canKick` whether to show a
/// kick option on someone else's.
@MainActor
final class ClubMemberListViewModel: ObservableObject {
    @Published private(set) var members: [ClubMember] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLeaving = false
    @Published private(set) var isKicking = false
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

    /// The caller's own role in THIS club, derived from the already-loaded `members` list — no second
    /// endpoint, `members` already carries every row's `role` including the caller's own.
    private var currentUserRole: String? {
        guard let currentUserId else { return nil }
        return members.first { $0.userId == currentUserId }?.role
    }

    /// Whether the caller can see the Circle Analytics entry point at all (product-spec.md §4.24
    /// AC12/AC14: owner/admin only, never shown to a plain member). The server re-checks this
    /// independently — this is purely to avoid showing a link that would just 403.
    var canViewAnalytics: Bool {
        currentUserRole == "owner" || currentUserRole == "admin"
    }

    /// Owner/admin only, and never on the caller's own row — self-leave is the separate, already-free
    /// path for that (server-side rejects a kick targeting yourself the same way, this is just so the
    /// button doesn't appear at all for a case that would 400).
    func canKick(_ member: ClubMember) -> Bool {
        guard let currentUserRole, currentUserRole == "owner" || currentUserRole == "admin" else { return false }
        return !isCurrentUser(member)
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

    func kick(clubId: String, member: ClubMember) async {
        guard !isKicking else { return }
        isKicking = true
        defer { isKicking = false }
        do {
            let jwt = try await currentJWT()
            _ = try await apiClient.kickMember(clubId: clubId, userId: member.userId, jwt: jwt)
            members.removeAll { $0.userId == member.userId }
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
        /// MOCK: preview-only state, never used by the app's real code paths. `apiClient`/`currentJWT`
        /// are overridable so a test can seed `members`/`currentUserId` directly (skipping `load()`)
        /// while still exercising a real network call for `kick(clubId:member:)`.
        init(
            apiClient: APIClient = APIClient(),
            currentJWT: @escaping @Sendable () async throws -> String = { "preview" },
            previewMembers: [ClubMember],
            currentUserId: String?
        ) {
            self.apiClient = apiClient
            self.currentJWT = currentJWT
            members = previewMembers
            self.currentUserId = currentUserId
        }
    #endif
}
