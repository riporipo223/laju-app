import Foundation

/// product-spec.md §4.24 AC12: Circle analytics — owner/admin of a Premium Club only.
/// `isPremiumRequired` follows the exact same 403 `not_premium_club` pattern
/// `CreateChallengeViewModel` uses.
@MainActor
final class ClubAnalyticsViewModel: ObservableObject {
    @Published private(set) var analytics: ClubAnalyticsResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var isPremiumRequired = false
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

    func load(clubId: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        isPremiumRequired = false
        defer { isLoading = false }
        do {
            let jwt = try await currentJWT()
            analytics = try await apiClient.fetchClubAnalytics(clubId: clubId, jwt: jwt)
        } catch let APIClientError.server(statusCode, body) where statusCode == 403 && body.contains("not_premium_club") {
            isPremiumRequired = true
        } catch is URLError {
            errorMessage = "Tidak ada koneksi. Coba lagi saat online."
        } catch {
            errorMessage = "Analytics belum bisa dimuat. Coba lagi."
        }
    }

    #if DEBUG
        /// MOCK: preview-only state, never used by the app's real code paths.
        init(previewAnalytics: ClubAnalyticsResponse) {
            apiClient = APIClient()
            currentJWT = { "preview" }
            analytics = previewAnalytics
        }
    #endif
}
