import Foundation

/// T4.1: Create Club state. Free for every tier (product-spec.md §4.24 AC1) — a prior version had an
/// `isPremiumRequired` flag for a 403 `not_premium` response; the server no longer sends that response
/// for this route (reverted 2026-09-26, HANDOFF.md "Audit drift 2026-09-26" item 2), so the flag is
/// gone too.
@MainActor
final class CreateClubViewModel: ObservableObject {
    @Published private(set) var isCreating = false
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
        defer { isCreating = false }

        do {
            let jwt = try await currentJWT()
            createdClub = try await apiClient.createClub(name: name, description: description, privacy: privacy, jwt: jwt)
        } catch let APIClientError.server(_, body) where body.lowercased().contains("already in a club") {
            errorMessage = "Kamu sudah tergabung di club lain."
        } catch is URLError {
            errorMessage = "Tidak ada koneksi. Coba lagi saat online."
        } catch {
            errorMessage = "Gagal bikin club. Coba lagi."
        }
    }

}
