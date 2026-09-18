import Foundation

enum APIClientError: Error, Equatable {
    case notAuthenticated
    case invalidResponse
    case server(statusCode: Int, body: String)
}

/// T2.14: thin `POST /api/runs` client. Holds no mutable state (just an injected `URLSession`), so it's a
/// plain `Sendable` struct — `session` defaults to `.shared` but tests inject a stub-configured session
/// (see `SyncServiceTests.swift`) via `URLProtocol` registration, since nothing in this codebase had a
/// URLSession injection seam before this task.
struct APIClient: Sendable {
    var session: URLSession = .shared

    /// `jwt` is the caller's responsibility to fetch fresh (see `SyncService`, which uses Supabase's own
    /// `auth.session` — auto-refreshing — rather than a possibly-stale cached token).
    func submitRun(_ request: SubmitRunRequest, jwt: String) async throws -> SubmitRunResponse {
        var urlRequest = URLRequest(url: APIConfig.baseURL.appendingPathComponent("api/runs"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try RunSubmissionCoding.makeEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        // T2.12d: a duplicate submission (same started_at) returns 200 with the existing run's result
        // instead of 201 — both are success from this client's point of view, same response shape.
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: body)
        }

        return try RunSubmissionCoding.makeDecoder().decode(SubmitRunResponse.self, from: data)
    }

    /// T2.14d: `GET /api/runs?since=` (database-api-spec.md §2.2b). `since == nil` omits the parameter
    /// entirely (server applies its own 90-day default lookback — the only legal first-ever call).
    func fetchRunStatuses(since: Date?, jwt: String) async throws -> ReconciliationResponse {
        var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent("api/runs"),
            resolvingAgainstBaseURL: false
        )
        if let since {
            components?.queryItems = [URLQueryItem(name: "since", value: ReconciliationCoding.sinceString(since))]
        }
        guard let url = components?.url else { throw APIClientError.invalidResponse }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: body)
        }

        return try RunSubmissionCoding.makeDecoder().decode(ReconciliationResponse.self, from: data)
    }

    /// T2.20: `GET /api/leaderboard?scope=global` (database-api-spec.md §2.4). `limit` is the top-N window; the
    /// caller's own rank comes back separately as `me`.
    func fetchLeaderboard(limit: Int, jwt: String) async throws -> LeaderboardResponse {
        var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent("api/leaderboard"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "scope", value: "global"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else { throw APIClientError.invalidResponse }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: body)
        }

        // Shared decoder: `computed_at` comes from PostgREST with microseconds (see `RunSubmissionCoding`).
        return try RunSubmissionCoding.makeDecoder().decode(LeaderboardResponse.self, from: data)
    }

    /// T2.16: `GET /api/users/me/progress` (database-api-spec.md §2.3) — server-authoritative points/level,
    /// consumed by `ProgressViewModel`.
    func fetchProgress(jwt: String) async throws -> ProgressResponse {
        var urlRequest = URLRequest(url: APIConfig.baseURL.appendingPathComponent("api/users/me/progress"))
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(ProgressResponse.self, from: data)
    }
}
