import Foundation

/// T4.21: gear (shoe) state for Save Activity's picker and the profile screen — both read/write the same
/// `gear` table (`backend/app/api/gear`), there is no run-scoped copy (phase-4-backlog.md T4.21 scope note).
@MainActor
final class GearViewModel: ObservableObject {
    /// T4.21 v1 scoping session, phase-4-backlog.md — must match `backend/app/api/gear/route.ts`'s
    /// `VALID_BRANDS` list exactly.
    static let brands = [
        "Nike", "Adidas", "Hoka", "Asics", "Brooks", "New Balance",
        "Saucony", "Puma", "Mizuno", "On", "Under Armour", "Other",
    ]

    @Published private(set) var gear: [Gear] = []
    @Published private(set) var isLoading = false
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

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let jwt = try await currentJWT()
            gear = try await apiClient.fetchGear(jwt: jwt).gear
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// - Returns: the newly-created gear on success, so the caller (Save Activity) can select it
    /// immediately without waiting for a reload.
    @discardableResult
    func addGear(brand: String, model: String?, size: String?) async -> Gear? {
        do {
            let jwt = try await currentJWT()
            let created = try await apiClient.createGear(brand: brand, model: model, size: size, jwt: jwt)
            gear.append(created)
            errorMessage = nil
            return created
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    private static func message(for error: Error) -> String {
        if error is URLError {
            return "Tidak ada koneksi. Coba lagi saat online."
        }
        return "Gagal memuat gear. Coba lagi."
    }

    #if DEBUG
        /// MOCK: preview-only state, never used by the app's real code paths.
        init(previewGear: [Gear]) {
            apiClient = APIClient()
            currentJWT = { "preview" }
            gear = previewGear
        }
    #endif
}
