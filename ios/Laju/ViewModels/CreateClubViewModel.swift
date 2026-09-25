import Foundation

/// T4.1: Create Club state. `isPremiumRequired` flips on a 403 `not_premium` — the view switches to the
/// upsell screen instead of showing a generic error, since that response is the expected, permanent
/// state until T4.20 ships (`lib/club/premium.ts`), not a transient failure to retry.
@MainActor
final class CreateClubViewModel: ObservableObject {
    @Published private(set) var isCreating = false
    @Published private(set) var isPremiumRequired = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var createdClub: CreateClubResponse?

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

    func createClub(name: String, description: String?, privacy: String) async {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        isPremiumRequired = false
        defer { isCreating = false }

        do {
            let jwt = try await currentJWT()
            createdClub = try await apiClient.createClub(name: name, description: description, privacy: privacy, jwt: jwt)
        } catch let APIClientError.server(statusCode, body) where statusCode == 403 && body.contains("not_premium") {
            isPremiumRequired = true
        } catch let APIClientError.server(_, body) where body.lowercased().contains("already in a club") {
            errorMessage = "Kamu sudah tergabung di club lain."
        } catch is URLError {
            errorMessage = "Tidak ada koneksi. Coba lagi saat online."
        } catch {
            errorMessage = "Gagal bikin club. Coba lagi."
        }
    }

    #if DEBUG
        /// MOCK: preview-only state, never used by the app's real code paths.
        init(previewPremiumRequired: Bool) {
            apiClient = APIClient()
            currentJWT = { "preview" }
            isPremiumRequired = previewPremiumRequired
        }
    #endif
}
