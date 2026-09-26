import Foundation

/// product-spec.md §4.24 AC13: create a Circle Challenge. `isPremiumRequired` flips on a 403
/// `not_premium_club` — the view switches to an upsell screen instead of a generic error, same
/// pattern `CreateClubViewModel` used before its own Premium gate was reverted (that flag is gone
/// there; this one is real, since Circle Challenge genuinely IS Premium-gated, unlike Circle
/// creation itself).
@MainActor
final class CreateChallengeViewModel: ObservableObject {
    @Published private(set) var isCreating = false
    @Published private(set) var isPremiumRequired = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var createdChallenge: CreateChallengeResponse?

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

    func createChallenge(clubId: String, name: String, targetType: String, targetValue: Double, deadline: Date) async {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        isPremiumRequired = false
        defer { isCreating = false }

        do {
            let jwt = try await currentJWT()
            createdChallenge = try await apiClient.createChallenge(
                clubId: clubId, name: name, targetType: targetType, targetValue: targetValue, deadline: deadline, jwt: jwt
            )
        } catch let APIClientError.server(statusCode, body) where statusCode == 403 && body.contains("not_premium_club") {
            isPremiumRequired = true
        } catch let APIClientError.server(_, body) where body.lowercased().contains("challenge_active") {
            errorMessage = "Circle ini sudah punya challenge yang sedang berjalan."
        } catch is URLError {
            errorMessage = "Tidak ada koneksi. Coba lagi saat online."
        } catch {
            errorMessage = "Gagal bikin challenge. Coba lagi."
        }
    }
}
