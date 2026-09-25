@testable import Laju
import XCTest

/// T4.16: comment DTO decoding, `CommentViewModel`'s load/post/delete, and its optimistic-delete revert.
/// Reuses `StubURLProtocol` from `SyncServiceTests.swift`, same pattern as `SocialFeedTests.swift`.
@MainActor
final class CommentTests: XCTestCase {
    func testDecodesCommentListShape() throws {
        let json = """
        {"comments":[{"comment_id":"c1","post_id":"post-1","user_id":"usr-2","username":"budi_run",
        "display_name":"Budi","avatar_url":null,"content":"Nice run!",
        "created_at":"2026-09-25T10:00:00.000000+00:00"}]}
        """
        let decoded = try RunSubmissionCoding.makeDecoder().decode(CommentListResponse.self, from: Data(json.utf8))
        let comment = try XCTUnwrap(decoded.comments.first)
        XCTAssertEqual(comment.authorName, "Budi")
        XCTAssertEqual(comment.content, "Nice run!")
    }

    func testCommentViewModelLoadPopulatesComments() async throws {
        StubURLProtocol.requestHandler = { _ in
            (
                200,
                Data(
                    #"{"comments":[{"comment_id":"c1","post_id":"post-1","user_id":"usr-2","username":null,"display_name":null,"avatar_url":null,"content":"GG","created_at":"2026-09-25T10:00:00Z"}]}"#
                        .utf8
                )
            )
        }
        let model = CommentViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.load(postId: "post-1")
        XCTAssertEqual(model.comments.count, 1)
        XCTAssertEqual(model.comments.first?.content, "GG")
    }

    func testCommentViewModelPostCommentAppendsOnSuccess() async throws {
        StubURLProtocol.requestHandler = { _ in
            (
                201,
                Data(
                    #"{"comment_id":"c2","post_id":"post-1","user_id":"usr-1","content":"Mantap!","created_at":"2026-09-25T10:00:00Z"}"#
                        .utf8
                )
            )
        }
        let model = CommentViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        let posted = await model.postComment(postId: "post-1", content: "Mantap!")
        XCTAssertTrue(posted)
        XCTAssertEqual(model.comments.count, 1)
        XCTAssertEqual(model.comments.first?.commentId, "c2")
    }

    func testCommentViewModelPostCommentSetsErrorMessageOnTooLong() async throws {
        StubURLProtocol.requestHandler = { _ in (400, Data(#"{"error":"content may be at most 280 characters"}"#.utf8)) }
        let model = CommentViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        let posted = await model.postComment(postId: "post-1", content: String(repeating: "x", count: 281))
        XCTAssertFalse(posted)
        XCTAssertTrue(model.comments.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    func testIsOwnCommentTrueOnlyForCurrentUsersOwnComment() {
        let ownComment = SocialComment(
            commentId: "c1", postId: "post-1", userId: "usr-1", username: nil, displayName: nil,
            avatarURL: nil, content: "GG", createdAt: Date()
        )
        let othersComment = SocialComment(
            commentId: "c2", postId: "post-1", userId: "usr-2", username: nil, displayName: nil,
            avatarURL: nil, content: "Nice", createdAt: Date()
        )
        let model = CommentViewModel(previewComments: [ownComment, othersComment], currentUserId: "usr-1")
        XCTAssertTrue(model.isOwnComment(ownComment))
        XCTAssertFalse(model.isOwnComment(othersComment))
    }

    func testCommentViewModelDeleteCommentRevertsOnFailure() async throws {
        let comment = SocialComment(
            commentId: "c1", postId: "post-1", userId: "usr-1", username: nil, displayName: nil,
            avatarURL: nil, content: "GG", createdAt: Date()
        )
        StubURLProtocol.requestHandler = { _ in
            (200, Data(#"{"comments":[{"comment_id":"c1","post_id":"post-1","user_id":"usr-1","username":null,"display_name":null,"avatar_url":null,"content":"GG","created_at":"2026-09-25T10:00:00Z"}]}"#.utf8))
        }
        let model = CommentViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.load(postId: "post-1")
        XCTAssertEqual(model.comments.count, 1)

        StubURLProtocol.requestHandler = { _ in (500, Data(#"{"error":"db down"}"#.utf8)) }
        await model.deleteComment(postId: "post-1", comment: comment)
        XCTAssertEqual(model.comments.count, 1) // reverted, not stuck removed
        XCTAssertNotNil(model.errorMessage)
    }
}
