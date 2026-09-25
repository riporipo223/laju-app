import Foundation

/// T4.1: Create Club only (`backend/app/api/clubs`). Reuses the same request-building shape
/// `APIClient+Social.swift` established, not a copy of `APIClient+ClubWar.swift`'s error-code mapping —
/// this route answers plain `{error, code?}` bodies, same as `/api/social/posts`.
extension APIClient {
    func createClub(name: String, description: String?, privacy: String, jwt: String) async throws -> CreateClubResponse {
        var urlRequest = URLRequest(url: APIConfig.baseURL.appendingPathComponent("api/clubs"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try RunSubmissionCoding.makeEncoder().encode(
            CreateClubRequest(name: name, description: description, privacy: privacy)
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard httpResponse.statusCode == 201 else {
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try RunSubmissionCoding.makeDecoder().decode(CreateClubResponse.self, from: data)
    }
}
