import Foundation

private struct CurrentUserResponse: Decodable {
    let id: String
}

/// T4.15: Social Feed endpoints (`backend/app/api/social/posts`). Not callable against the live backend yet
/// — see `SocialDTOs.swift`'s header comment.
extension APIClient {
    /// Resolves the caller's own `user.id` (not `auth_user_id`) — needed by `SocialViewModel` to tell "my
    /// own post" apart from everyone else's in the feed (so it can show the delete-own-post control, v1's
    /// only moderation path). Reuses `GET /api/auth/me` (T2.3, already deployed, `backend/app/api/auth/me/
    /// route.ts`) rather than adding a new endpoint — `APIClient+Profile.swift`'s `hasProfile` already calls
    /// this same route but only reads its 401 body; this reads the 200 body instead.
    func fetchCurrentUserId(jwt: String) async throws -> String {
        var urlRequest = URLRequest(url: APIConfig.baseURL.appendingPathComponent("api/auth/me"))
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            throw APIClientError.server(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(CurrentUserResponse.self, from: data).id
    }

    /// `before` paginates backwards (older posts) using the previous page's `nextBefore`; `nil` fetches the
    /// newest page. `limit` defaults to the server's own default (20) when `nil`.
    func fetchSocialFeed(before: Date?, limit: Int?, jwt: String) async throws -> SocialFeedResponse {
        var queryItems: [URLQueryItem] = []
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: ReconciliationCoding.sinceString(before)))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        return try await sendSocial(
            path: "api/social/posts",
            method: "GET",
            body: nil,
            queryItems: queryItems,
            jwt: jwt,
            expecting: [200]
        )
    }

    /// T4.21: `mapType`/`visibility`/`gearId` are `nil` for the plain Run History posting flow (server
    /// defaults apply — "standard"/"public"/no gear); Save Activity passes real values for all of them.
    func createSocialPost(
        runId: String,
        caption: String?,
        title: String? = nil,
        description: String? = nil,
        privateNotes: String? = nil,
        mapType: String? = nil,
        visibility: String? = nil,
        gearId: String? = nil,
        jwt: String
    ) async throws -> CreateSocialPostResponse {
        let body = try RunSubmissionCoding.makeEncoder().encode(
            CreateSocialPostRequest(
                runId: runId,
                caption: caption,
                title: title,
                description: description,
                privateNotes: privateNotes,
                mapType: mapType,
                visibility: visibility,
                gearId: gearId
            )
        )
        return try await sendSocial(
            path: "api/social/posts",
            method: "POST",
            body: body,
            queryItems: [],
            jwt: jwt,
            expecting: [201]
        )
    }

    /// T4.21: the caller's own gear list, for Save Activity's prefill and the profile screen.
    func fetchGear(jwt: String) async throws -> GearListResponse {
        try await sendSocial(path: "api/gear", method: "GET", body: nil, queryItems: [], jwt: jwt, expecting: [200])
    }

    /// T4.21: add a shoe — used both from Save Activity's inline "Add Gear" and the profile screen.
    func createGear(brand: String, model: String?, size: String?, jwt: String) async throws -> Gear {
        let body = try RunSubmissionCoding.makeEncoder().encode(CreateGearRequest(brand: brand, model: model, size: size))
        return try await sendSocial(path: "api/gear", method: "POST", body: body, queryItems: [], jwt: jwt, expecting: [201])
    }

    /// v1 moderation is delete-own-post only (phase-4-backlog.md T4.15) — the server scopes this to the
    /// caller's own posts and answers 404 either way, never a 403.
    func deleteSocialPost(postId: String, jwt: String) async throws -> DeleteSocialPostResponse {
        try await sendSocial(
            path: "api/social/posts/\(postId)",
            method: "DELETE",
            body: nil,
            queryItems: [],
            jwt: jwt,
            expecting: [200]
        )
    }

    func likeSocialPost(postId: String, jwt: String) async throws -> SocialLikeResponse {
        try await sendSocial(
            path: "api/social/posts/\(postId)/like",
            method: "POST",
            body: nil,
            queryItems: [],
            jwt: jwt,
            expecting: [200]
        )
    }

    /// T4.16: a post's comments, oldest-first — `backend/app/api/social/posts/[id]/comments`.
    func fetchComments(postId: String, jwt: String) async throws -> CommentListResponse {
        try await sendSocial(
            path: "api/social/posts/\(postId)/comments",
            method: "GET",
            body: nil,
            queryItems: [],
            jwt: jwt,
            expecting: [200]
        )
    }

    func createComment(postId: String, content: String, jwt: String) async throws -> SocialComment {
        let body = try RunSubmissionCoding.makeEncoder().encode(CreateCommentRequest(content: content))
        return try await sendSocial(
            path: "api/social/posts/\(postId)/comments",
            method: "POST",
            body: body,
            queryItems: [],
            jwt: jwt,
            expecting: [201]
        )
    }

    /// v1 moderation is delete-own-comment only (phase-4-backlog.md T4.16) — same shape as
    /// `deleteSocialPost`: the server scopes this to the caller's own comment and answers 404 either way.
    func deleteComment(postId: String, commentId: String, jwt: String) async throws -> DeleteCommentResponse {
        try await sendSocial(
            path: "api/social/posts/\(postId)/comments/\(commentId)",
            method: "DELETE",
            body: nil,
            queryItems: [],
            jwt: jwt,
            expecting: [200]
        )
    }

    func unlikeSocialPost(postId: String, jwt: String) async throws -> SocialLikeResponse {
        try await sendSocial(
            path: "api/social/posts/\(postId)/like",
            method: "DELETE",
            body: nil,
            queryItems: [],
            jwt: jwt,
            expecting: [200]
        )
    }

    private func sendSocial<Response: Decodable>(
        path: String,
        method: String,
        body: Data?,
        queryItems: [URLQueryItem],
        jwt: String,
        expecting okStatuses: Set<Int>
    ) async throws -> Response {
        var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw APIClientError.invalidResponse }

        var urlRequest = URLRequest(url: url)
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
