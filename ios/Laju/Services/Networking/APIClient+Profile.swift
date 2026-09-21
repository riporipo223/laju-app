import Foundation

/// The two calls the onboarding profile step needs. Until 2026-09-21 the app never called `POST /api/profile/complete`
/// at all (T2.4's mobile half was blocked on sign-in), so a real new user could not submit a run — the server answers
/// `409` without a region — and every end-to-end check had to seed the profile straight into the database.
extension APIClient {
    /// `GET /api/auth/me`: `true` when the signed-in identity already has a profile, `false` on the server's
    /// `profile_missing` 401. Anything else (a broken token, a 5xx) is an error, not "no profile".
    func hasProfile(jwt: String) async throws -> Bool {
        var urlRequest = URLRequest(url: APIConfig.baseURL.appendingPathComponent("api/auth/me"))
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        switch httpResponse.statusCode {
        case 200:
            return true
        case 401 where (try? JSONDecoder().decode(AuthErrorBody.self, from: data))?.code == "profile_missing":
            return false
        default:
            throw APIClientError.server(
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    /// `POST /api/profile/complete` — creates the `user` row (an upsert on the server, so a repeat is harmless).
    func completeProfile(_ request: CompleteProfileRequest, jwt: String) async throws {
        var urlRequest = URLRequest(url: APIConfig.baseURL.appendingPathComponent("api/profile/complete"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw APIClientError.server(
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }
}
