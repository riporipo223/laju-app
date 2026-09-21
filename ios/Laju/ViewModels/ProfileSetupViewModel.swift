import Foundation

/// State and validation of the onboarding profile step (username + the three region fields, AC 4.1.2 / T2.4 / T3.1).
///
/// Region is FREE TEXT for now: a proper catalog (thousands of Indonesian kecamatan, wireframe-spec.md §8's cascading
/// picker) does not exist yet, and the server validates presence only. The trade-off is dirty data — the same kecamatan
/// spelled several ways — which the deferred Local Leaderboard will have to normalize before it groups by region. Input
/// is trimmed here, nothing more. When the picker is built (T3.1) it replaces these three fields.
@MainActor
final class ProfileSetupViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case submitting
        case failed(String)
    }

    @Published var username = ""
    @Published var kecamatan = ""
    @Published var kabupatenKota = ""
    @Published var provinsi = ""
    @Published private(set) var state: State = .idle

    static let usernameLength = 3 ... 24
    static let regionMaxLength = 100

    private let apiClient: APIClient
    private let accessToken: @Sendable () async throws -> String

    init(apiClient: APIClient = APIClient(), accessToken: @escaping @Sendable () async throws -> String) {
        self.apiClient = apiClient
        self.accessToken = accessToken
    }

    /// The trimmed, validated request, or `nil` while any field is missing or malformed.
    var request: CompleteProfileRequest? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let regions = [kecamatan, kabupatenKota, provinsi].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard Self.isValidUsername(name),
              regions.allSatisfy({ !$0.isEmpty && $0.count <= Self.regionMaxLength })
        else { return nil }
        return CompleteProfileRequest(
            username: name,
            regionKecamatan: regions[0],
            regionKabupatenKota: regions[1],
            regionProvinsi: regions[2]
        )
    }

    var canSubmit: Bool {
        request != nil && state != .submitting
    }

    /// Letters, digits and underscore, 3–24 characters — it is shown on the leaderboard, so nothing exotic.
    static func isValidUsername(_ name: String) -> Bool {
        usernameLength.contains(name.count)
            && name.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_") }
    }

    /// - Returns: `true` once the server has stored the profile; on failure `state` carries the message to show.
    func submit() async -> Bool {
        guard let request, state != .submitting else { return false }
        state = .submitting
        do {
            let jwt = try await accessToken()
            try await apiClient.completeProfile(request, jwt: jwt)
            state = .idle
            return true
        } catch {
            state = .failed(Self.message(for: error))
            return false
        }
    }

    static func message(for error: Error) -> String {
        if case let APIClientError.server(statusCode, _) = error {
            switch statusCode {
            case 400: return "Isian belum lengkap atau tidak valid. Periksa lagi."
            case 401: return "Sesi masuk berakhir. Masuk lagi lalu coba simpan."
            case 429: return "Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi."
            default: break
            }
        }
        if error is URLError {
            return "Tidak ada koneksi. Coba lagi saat online."
        }
        return "Gagal menyimpan profil. Coba lagi."
    }
}
