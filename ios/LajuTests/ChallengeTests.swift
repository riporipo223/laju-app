@testable import Laju
import XCTest

/// product-spec.md §4.24 AC13: `ChallengeViewModel`'s load (progress/ranking/empty-state/ownership)
/// and cancel. Reuses `StubURLProtocol`, routing by request path the same way
/// `ClubBrowseTests.testClubMemberListViewModelLeaveRemovesCallersOwnRow` already established for a
/// multi-endpoint load.
@MainActor
final class ChallengeTests: XCTestCase {
    private func handler(currentUserId: String, members: String, challenge: (Int, String)) -> @Sendable (URLRequest) -> (Int, Data) {
        { request in
            if request.url?.path.hasSuffix("/auth/me") == true {
                return (200, Data(#"{"id":"\#(currentUserId)"}"#.utf8))
            }
            if request.url?.path.hasSuffix("/members") == true {
                return (200, Data(members.utf8))
            }
            return (challenge.0, Data(challenge.1.utf8))
        }
    }

    func testLoadPopulatesChallengeProgressAndRanking() async throws {
        StubURLProtocol.requestHandler = handler(
            currentUserId: "usr-1",
            members: #"{"members":[{"user_id":"usr-1","username":null,"display_name":null,"avatar_url":null,"role":"owner","joined_at":"2026-09-01T10:00:00Z"}]}"#,
            challenge: (
                200,
                #"{"challenge_id":"ch1","club_id":"c1","name":"500km bareng","target_type":"distance","target_value":500000,"deadline":"2026-10-26T10:00:00Z","status":"active","collective_total":120000,"ranking":[{"user_id":"usr-1","total":120000}]}"#
            )
        )
        let model = ChallengeViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.load(clubId: "c1")
        XCTAssertFalse(model.hasNoChallenge)
        XCTAssertEqual(model.challenge?.collectiveTotal, 120000)
        XCTAssertEqual(model.challenge?.ranking.first?.userId, "usr-1")
        XCTAssertTrue(model.isOwner)
    }

    func testLoadSetsHasNoChallengeOn404() async throws {
        StubURLProtocol.requestHandler = handler(
            currentUserId: "usr-1",
            members: #"{"members":[{"user_id":"usr-1","username":null,"display_name":null,"avatar_url":null,"role":"owner","joined_at":"2026-09-01T10:00:00Z"}]}"#,
            challenge: (404, #"{"error":"This Circle has no challenge"}"#)
        )
        let model = ChallengeViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.load(clubId: "c1")
        XCTAssertTrue(model.hasNoChallenge)
        XCTAssertNil(model.challenge)
    }

    func testLoadSetsIsOwnerFalseForAPlainMember() async throws {
        StubURLProtocol.requestHandler = handler(
            currentUserId: "usr-2",
            members: #"{"members":[{"user_id":"usr-1","username":null,"display_name":null,"avatar_url":null,"role":"owner","joined_at":"2026-09-01T10:00:00Z"},{"user_id":"usr-2","username":null,"display_name":null,"avatar_url":null,"role":"member","joined_at":"2026-09-05T10:00:00Z"}]}"#,
            challenge: (404, #"{"error":"This Circle has no challenge"}"#)
        )
        let model = ChallengeViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.load(clubId: "c1")
        XCTAssertFalse(model.isOwner)
    }

    func testCancelSetsDidCancelAndReloadsTheFrozenChallenge() async throws {
        StubURLProtocol.requestHandler = { request in
            if request.url?.path.hasSuffix("/auth/me") == true {
                return (200, Data(#"{"id":"usr-1"}"#.utf8))
            }
            if request.url?.path.hasSuffix("/members") == true {
                return (200, Data(#"{"members":[{"user_id":"usr-1","username":null,"display_name":null,"avatar_url":null,"role":"owner","joined_at":"2026-09-01T10:00:00Z"}]}"#.utf8))
            }
            if request.httpMethod == "DELETE" {
                return (200, Data(#"{"challenge_id":"ch1","cancelled":true}"#.utf8))
            }
            return (
                200,
                Data(
                    #"{"challenge_id":"ch1","club_id":"c1","name":"500km bareng","target_type":"distance","target_value":500000,"deadline":"2026-10-26T10:00:00Z","status":"cancelled","collective_total":120000,"ranking":[]}"#
                        .utf8
                )
            )
        }
        let model = ChallengeViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.load(clubId: "c1")
        await model.cancel(clubId: "c1")
        XCTAssertTrue(model.didCancel)
        XCTAssertEqual(model.challenge?.status, "cancelled")
    }
}
