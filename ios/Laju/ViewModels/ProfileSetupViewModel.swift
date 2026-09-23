import Foundation

/// State and validation of the onboarding profile step (username only).
///
/// The three free-text region fields were REMOVED 2026-09-22 (decision D1 reversed — product-spec.md §4.1). Region was
/// only ever collected to prepare data for the Local Leaderboard, which was cancelled permanently (§4.6), so there is
/// nothing left to prepare for and the cascading-picker work (wireframe-spec.md §8) is cancelled with it. Leaderboard
/// access is now gated on granted location permission instead (§4.5 AC5) — a gate that needs no profile field at all.
@MainActor
final class ProfileSetupViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case submitting
        case failed(String)
    }

    @Published var username = ""
    @Published private(set) var state: State = .idle

    static let usernameLength = 3 ... 24

    private let apiClient: APIClient
    private let accessToken: @Sendable () async throws -> String

    init(apiClient: APIClient = APIClient(), accessToken: @escaping @Sendable () async throws -> String) {
        self.apiClient = apiClient
        self.accessToken = accessToken
    }

    /// The trimmed, validated request, or `nil` while the username is missing or malformed.
    var request: CompleteProfileRequest? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidUsername(name) else { return nil }
        return CompleteProfileRequest(username: name)
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
