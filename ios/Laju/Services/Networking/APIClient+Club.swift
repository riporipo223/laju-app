import Foundation

/// T4.1: `backend/app/api/clubs/*` — Create Club (T4.1) plus browse/join/leave/member list (T4.1b,
/// 2026-09-25). Reuses the same request-building shape `APIClient+Social.swift` established, not a copy
/// of `APIClient+ClubWar.swift`'s error-code mapping — these routes answer plain `{error, code?}` bodies,
/// same as `/api/social/posts`.
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

    /// `before` paginates backwards (older clubs) — same cursor semantics `fetchSocialFeed` already uses.
    func browseClubs(before: Date?, limit: Int?, jwt: String) async throws -> ClubBrowseResponse {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent("api/clubs"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: ReconciliationCoding.sinceString(before)))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw APIClientError.invalidResponse }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try RunSubmissionCoding.makeDecoder().decode(ClubBrowseResponse.self, from: data)
    }

    func fetchClubMembers(clubId: String, jwt: String) async throws -> ClubMemberListResponse {
        var urlRequest = URLRequest(url: APIConfig.baseURL.appendingPathComponent("api/clubs/\(clubId)/members"))
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try RunSubmissionCoding.makeDecoder().decode(ClubMemberListResponse.self, from: data)
    }

    /// `inviteCode` is `nil` for a public club — the server ignores it entirely for `privacy = "public"`.
    func joinClub(clubId: String, inviteCode: String?, jwt: String) async throws -> JoinClubResponse {
        var urlRequest = URLRequest(url: APIConfig.baseURL.appendingPathComponent("api/clubs/\(clubId)/join"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try RunSubmissionCoding.makeEncoder().encode(JoinClubRequest(inviteCode: inviteCode))

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try RunSubmissionCoding.makeDecoder().decode(JoinClubResponse.self, from: data)
    }

    /// Self-leave only (v1 scope) — always the caller's own membership, no `userId` parameter needed.
    func leaveClub(clubId: String, jwt: String) async throws -> LeaveClubResponse {
        var urlRequest = URLRequest(url: APIConfig.baseURL.appendingPathComponent("api/clubs/\(clubId)/members"))
        urlRequest.httpMethod = "DELETE"
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try RunSubmissionCoding.makeDecoder().decode(LeaveClubResponse.self, from: data)
    }

    /// product-spec.md §4.24 AC23: same endpoint as `leaveClub`, a `user_id` body distinguishes it
    /// server-side — gated only on the caller being owner/admin, never Premium.
    func kickMember(clubId: String, userId: String, jwt: String) async throws -> KickMemberResponse {
        var urlRequest = URLRequest(url: APIConfig.baseURL.appendingPathComponent("api/clubs/\(clubId)/members"))
        urlRequest.httpMethod = "DELETE"
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try RunSubmissionCoding.makeEncoder().encode(KickMemberRequest(userId: userId))

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try RunSubmissionCoding.makeDecoder().decode(KickMemberResponse.self, from: data)
    }
}
