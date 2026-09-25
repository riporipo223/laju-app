@testable import Laju
import XCTest

/// T4.1b: browse/join DTO decoding, `ClubBrowseViewModel`'s load/join, and `ClubMemberListViewModel`'s
/// load/leave. Reuses `StubURLProtocol` from `SyncServiceTests.swift`, same pattern as `CreateClubTests.swift`.
@MainActor
final class ClubBrowseTests: XCTestCase {
    func testDecodesBrowseResponseWithNoInviteCodeField() throws {
        let json = """
        {"clubs":[{"club_id":"c1","name":"Lari Pagi","description":null,"privacy":"public",
        "member_count":3,"created_at":"2026-09-25T10:00:00.000000+00:00"}],"has_more":false,"next_before":null}
        """
        let decoded = try RunSubmissionCoding.makeDecoder().decode(ClubBrowseResponse.self, from: Data(json.utf8))
        let club = try XCTUnwrap(decoded.clubs.first)
        XCTAssertEqual(club.memberCount, 3)
        XCTAssertEqual(club.privacy, "public")
    }

    func testClubBrowseViewModelLoadPopulatesClubs() async throws {
        StubURLProtocol.requestHandler = { _ in
            (
                200,
                Data(
                    #"{"clubs":[{"club_id":"c1","name":"Lari Pagi","description":null,"privacy":"public","member_count":1,"created_at":"2026-09-25T10:00:00Z"}],"has_more":false,"next_before":null}"#
                        .utf8
                )
            )
        }
        let model = ClubBrowseViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.load()
        XCTAssertEqual(model.clubs.count, 1)
        XCTAssertEqual(model.clubs.first?.name, "Lari Pagi")
    }

    func testJoinClubSucceedsForPublicClub() async throws {
        let club = ClubSummary(clubId: "c1", name: "Lari Pagi", description: nil, privacy: "public", memberCount: 1, createdAt: Date())
        StubURLProtocol.requestHandler = { _ in (200, Data(#"{"club_id":"c1","joined":true}"#.utf8)) }
        let model = ClubBrowseViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        let joined = await model.joinClub(club, inviteCode: nil)
        XCTAssertTrue(joined)
        XCTAssertNil(model.invitePromptClubId)
    }

    func testJoinClubSetsInvitePromptOn403ForInviteOnlyClub() async throws {
        let club = ClubSummary(clubId: "c1", name: "Elite", description: nil, privacy: "invite_only", memberCount: 1, createdAt: Date())
        StubURLProtocol.requestHandler = { _ in (403, Data(#"{"error":"Invalid or missing invite code"}"#.utf8)) }
        let model = ClubBrowseViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        let joined = await model.joinClub(club, inviteCode: "wrong")
        XCTAssertFalse(joined)
        XCTAssertEqual(model.invitePromptClubId, "c1")
        XCTAssertNil(model.errorMessage) // invite prompt is its own state, not a generic error
    }

    func testJoinClubSetsErrorMessageWhenAlreadyInAClub() async throws {
        let club = ClubSummary(clubId: "c1", name: "Lari Pagi", description: nil, privacy: "public", memberCount: 1, createdAt: Date())
        StubURLProtocol.requestHandler = { _ in (409, Data(#"{"error":"You are already in a club"}"#.utf8)) }
        let model = ClubBrowseViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        let joined = await model.joinClub(club, inviteCode: nil)
        XCTAssertFalse(joined)
        XCTAssertNotNil(model.errorMessage)
    }

    func testClubMemberListViewModelLoadPopulatesMembers() async throws {
        StubURLProtocol.requestHandler = { _ in
            (
                200,
                Data(
                    #"{"members":[{"user_id":"usr-1","username":"budi_run","display_name":"Budi","avatar_url":null,"role":"owner","joined_at":"2026-09-25T10:00:00Z"}]}"#
                        .utf8
                )
            )
        }
        let model = ClubMemberListViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.load(clubId: "c1")
        XCTAssertEqual(model.members.count, 1)
        XCTAssertEqual(model.members.first?.displayLabel, "Budi")
    }

    func testClubMemberListViewModelLeaveRemovesCallersOwnRow() async throws {
        let member = ClubMember(userId: "usr-1", username: nil, displayName: nil, avatarURL: nil, role: "member", joinedAt: Date())
        let model = ClubMemberListViewModel(previewMembers: [member], currentUserId: "usr-1")
        XCTAssertTrue(model.isCurrentUser(member))

        let liveModel = ClubMemberListViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        // `load()` also calls `fetchCurrentUserId` (GET /api/auth/me) before the member list — route by
        // path so that call doesn't get the member-list JSON and silently fail to decode (leaving
        // currentUserId nil, which would make isCurrentUser always false further down).
        StubURLProtocol.requestHandler = { request in
            if request.url?.path.hasSuffix("/auth/me") == true {
                return (200, Data(#"{"id":"usr-1"}"#.utf8))
            }
            return (200, Data(#"{"members":[{"user_id":"usr-1","username":null,"display_name":null,"avatar_url":null,"role":"member","joined_at":"2026-09-25T10:00:00Z"}]}"#.utf8))
        }
        await liveModel.load(clubId: "c1")
        XCTAssertEqual(liveModel.members.count, 1)

        StubURLProtocol.requestHandler = { _ in (200, Data(#"{"club_id":"c1","left":true}"#.utf8)) }
        await liveModel.leave(clubId: "c1")
        XCTAssertTrue(liveModel.didLeave)
        XCTAssertTrue(liveModel.members.isEmpty)
    }
}
