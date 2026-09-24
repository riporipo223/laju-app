@testable import Laju
import XCTest

/// T4.15: Social Feed wire decoding, request shape, and the view model's pure/optimistic-update rules.
/// The JSON below is exactly what `backend/app/api/social/posts/*` (T4.15) produce. Reuses `StubURLProtocol`
/// from `SyncServiceTests.swift`, same pattern as `ClubWarTests.swift`.
@MainActor
final class SocialFeedTests: XCTestCase {
    private let feedJSON = """
    {"posts":[{"post_id":"post-1","user_id":"usr-2","username":"budi_run","display_name":"Budi",
    "avatar_url":null,"run_id":"run-1","distance_meters":5230,"duration_seconds":1830,
    "avg_pace_sec_per_km":350,"final_points_awarded":6,"caption":"Lari pagi!",
    "created_at":"2026-09-24T10:00:00.123456+00:00","like_count":2,"liked_by_caller":true}],
    "has_more":true,"next_before":"2026-09-24T10:00:00.123456+00:00"}
    """

    func testDecodesTheFeedShapeIncludingMicrosecondTimestamps() throws {
        let decoded = try RunSubmissionCoding.makeDecoder().decode(SocialFeedResponse.self, from: Data(feedJSON.utf8))
        XCTAssertTrue(decoded.hasMore)
        XCTAssertNotNil(decoded.nextBefore)
        let post = try XCTUnwrap(decoded.posts.first)
        XCTAssertEqual(post.postId, "post-1")
        XCTAssertEqual(post.authorName, "Budi")
        XCTAssertEqual(post.distanceMeters, 5230)
        XCTAssertEqual(post.likeCount, 2)
        XCTAssertTrue(post.likedByCaller)
    }

    func testAuthorNameFallsBackToUsernameThenAGenericLabel() {
        let base = SocialPost(
            postId: "p", userId: "u", username: nil, displayName: nil, avatarURL: nil, runId: "r",
            distanceMeters: nil, durationSeconds: nil, avgPaceSecPerKm: nil, finalPointsAwarded: nil,
            caption: nil, createdAt: Date(), likeCount: 0, likedByCaller: false
        )
        XCTAssertEqual(base.authorName, "Pelari Laju")

        let withUsername = SocialPost(
            postId: "p", userId: "u", username: "budi_run", displayName: nil, avatarURL: nil, runId: "r",
            distanceMeters: nil, durationSeconds: nil, avgPaceSecPerKm: nil, finalPointsAwarded: nil,
            caption: nil, createdAt: Date(), likeCount: 0, likedByCaller: false
        )
        XCTAssertEqual(withUsername.authorName, "budi_run")
    }

    func testDecodesTheCreateResponseShape() throws {
        let json = #"{"post_id":"post-9","run_id":"run-9","caption":null,"created_at":"2026-09-24T10:00:00Z"}"#
        let decoded = try RunSubmissionCoding.makeDecoder().decode(CreateSocialPostResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.postId, "post-9")
        XCTAssertNil(decoded.caption)
    }

    func testCreateSendsRunIdAndCaptionWithTheBearerToken() async throws {
        let box = SocialRequestBox()
        StubURLProtocol.requestHandler = { request in
            box.record(request)
            return (201, Data(#"{"post_id":"p1","run_id":"r1","caption":"GG","created_at":"2026-09-24T10:00:00Z"}"#.utf8))
        }
        let client = APIClient(session: StubURLProtocol.makeSession())
        let response = try await client.createSocialPost(runId: "r1", caption: "GG", jwt: "jwt-1")

        XCTAssertEqual(response.postId, "p1")
        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/social/posts")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-1")
        let body = try XCTUnwrap(box.body)
        let decodedBody = try JSONDecoder().decode(CreateSocialPostRequest.self, from: body)
        XCTAssertEqual(decodedBody.runId, "r1")
        XCTAssertEqual(decodedBody.caption, "GG")
    }

    func testFetchFeedSendsBeforeAndLimitAsQueryItems() async throws {
        let box = SocialRequestBox()
        StubURLProtocol.requestHandler = { request in
            box.record(request)
            return (200, Data(#"{"posts":[],"has_more":false,"next_before":null}"#.utf8))
        }
        let client = APIClient(session: StubURLProtocol.makeSession())
        let cursor = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await client.fetchSocialFeed(before: cursor, limit: 10, jwt: "jwt-1")

        let request = try XCTUnwrap(box.request)
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["limit"], "10")
        XCTAssertEqual(items["before"], ReconciliationCoding.sinceString(cursor))
    }

    func testDeleteAndUnlikeUseTheRightMethodAndPath() async throws {
        let box = SocialRequestBox()
        StubURLProtocol.requestHandler = { request in
            box.record(request)
            return (200, Data(#"{"post_id":"p1","deleted":true}"#.utf8))
        }
        let client = APIClient(session: StubURLProtocol.makeSession())
        _ = try await client.deleteSocialPost(postId: "p1", jwt: "jwt-1")
        let deleteRequest = try XCTUnwrap(box.request)
        XCTAssertEqual(deleteRequest.httpMethod, "DELETE")
        XCTAssertEqual(deleteRequest.url?.path, "/api/social/posts/p1")

        StubURLProtocol.requestHandler = { request in
            box.record(request)
            return (200, Data(#"{"post_id":"p1","liked":false,"like_count":0}"#.utf8))
        }
        _ = try await client.unlikeSocialPost(postId: "p1", jwt: "jwt-1")
        let unlikeRequest = try XCTUnwrap(box.request)
        XCTAssertEqual(unlikeRequest.httpMethod, "DELETE")
        XCTAssertEqual(unlikeRequest.url?.path, "/api/social/posts/p1/like")
    }

    func testErrorMessagesMapKnownServerCopyAndFallBackOtherwise() {
        XCTAssertEqual(
            SocialViewModel.message(for: APIClientError.server(statusCode: 422, body: "Only a validated or approved run can be posted")),
            "Lari ini belum bisa diposting — tunggu sampai statusnya valid."
        )
        XCTAssertEqual(
            SocialViewModel.message(for: APIClientError.server(statusCode: 403, body: "You can only post your own runs")),
            "Kamu cuma bisa post lari kamu sendiri."
        )
        XCTAssertEqual(
            SocialViewModel.message(for: URLError(.notConnectedToInternet)),
            "Tidak ada koneksi. Coba lagi saat online."
        )
        XCTAssertEqual(
            SocialViewModel.message(for: APIClientError.server(statusCode: 500, body: "")),
            "Feed belum bisa dimuat. Coba lagi."
        )
    }

    func testToggleLikeIsOptimisticThenReconcilesWithTheServersCount() async throws {
        let post = SocialPost(
            postId: "p1", userId: "usr-2", username: nil, displayName: nil, avatarURL: nil, runId: "r1",
            distanceMeters: nil, durationSeconds: nil, avgPaceSecPerKm: nil, finalPointsAwarded: nil,
            caption: nil, createdAt: Date(), likeCount: 2, likedByCaller: false
        )
        StubURLProtocol.requestHandler = { _ in (200, Data(#"{"post_id":"p1","liked":true,"like_count":9}"#.utf8)) }
        let model = SocialViewModel(
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: { "jwt-1" }
        )
        model.seedForTest(posts: [post])

        await model.toggleLike(post)

        XCTAssertEqual(model.posts.first?.likedByCaller, true)
        XCTAssertEqual(model.posts.first?.likeCount, 9) // server's authoritative count, not the optimistic 3
    }

    func testToggleLikeRevertsOnFailure() async throws {
        let post = SocialPost(
            postId: "p1", userId: "usr-2", username: nil, displayName: nil, avatarURL: nil, runId: "r1",
            distanceMeters: nil, durationSeconds: nil, avgPaceSecPerKm: nil, finalPointsAwarded: nil,
            caption: nil, createdAt: Date(), likeCount: 2, likedByCaller: false
        )
        StubURLProtocol.requestHandler = { _ in (500, Data(#"{"error":"db down"}"#.utf8)) }
        let model = SocialViewModel(
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: { "jwt-1" }
        )
        model.seedForTest(posts: [post])

        await model.toggleLike(post)

        XCTAssertEqual(model.posts.first?.likedByCaller, false) // reverted, not stuck on the optimistic flip
        XCTAssertEqual(model.posts.first?.likeCount, 2)
        XCTAssertNotNil(model.errorMessage)
    }

    func testDeletePostRemovesOptimisticallyAndRestoresOnFailure() async throws {
        let post = SocialPost(
            postId: "p1", userId: "usr-1", username: nil, displayName: nil, avatarURL: nil, runId: "r1",
            distanceMeters: nil, durationSeconds: nil, avgPaceSecPerKm: nil, finalPointsAwarded: nil,
            caption: nil, createdAt: Date(), likeCount: 0, likedByCaller: false
        )
        StubURLProtocol.requestHandler = { _ in (500, Data(#"{"error":"db down"}"#.utf8)) }
        let model = SocialViewModel(
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: { "jwt-1" }
        )
        model.seedForTest(posts: [post])

        await model.deletePost(post)

        XCTAssertEqual(model.posts.count, 1) // the failed delete restored the row
    }
}

/// Captures the request the stub saw. A `URLProtocol` receives the body as a stream, not `httpBody`, so it
/// is read here — same pattern as `ProfileSetupTests.swift`'s private `Seen`.
private final class SocialRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?
    private var storedBody: Data?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    var body: Data? {
        lock.lock()
        defer { lock.unlock() }
        return storedBody
    }

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequest = request
        storedBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 {
                    break
                }
                data.append(buffer, count: read)
            }
            return data
        }
    }
}
