import Foundation

/// T4.2c: Club War endpoints (T4.2b). Not callable against the live backend yet — see `ClubWarDTOs.swift`.
extension APIClient {
    func fetchClubWars(jwt: String) async throws -> ClubWarListResponse {
        try await sendClubWar(path: "api/club-wars", method: "GET", body: nil, jwt: jwt, expecting: [200])
    }

    func fetchClubWarRecord(jwt: String) async throws -> ClubWarRecordResponse {
        try await sendClubWar(path: "api/club-wars/record", method: "GET", body: nil, jwt: jwt, expecting: [200])
    }

    func createClubWar(invitedClubIds: [String], jwt: String) async throws -> ClubWarStatusResponse {
        let body = try JSONEncoder().encode(CreateClubWarRequest(invitedClubIds: invitedClubIds))
        return try await sendClubWar(path: "api/club-wars", method: "POST", body: body, jwt: jwt, expecting: [201])
    }

    func respondToClubWar(warId: String, accept: Bool, jwt: String) async throws -> ClubWarStatusResponse {
        let body = try JSONEncoder().encode(RespondClubWarRequest(accept: accept))
        return try await sendClubWar(
            path: "api/club-wars/\(warId)/respond",
            method: "POST",
            body: body,
            jwt: jwt,
            expecting: [200]
        )
    }

    private func sendClubWar<Response: Decodable>(
        path: String,
        method: String,
        body: Data?,
        jwt: String,
        expecting okStatuses: Set<Int>
    ) async throws -> Response {
        var urlRequest = URLRequest(url: APIConfig.baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = body
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard okStatuses.contains(httpResponse.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: text)
        }
        return try RunSubmissionCoding.makeDecoder().decode(Response.self, from: data)
    }
}
