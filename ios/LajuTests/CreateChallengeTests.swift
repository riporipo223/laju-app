@testable import Laju
import XCTest

/// product-spec.md §4.24 AC13: `CreateChallengeViewModel`'s Premium-gate detection, active-challenge
/// rejection, and success path. Reuses `StubURLProtocol` from `SyncServiceTests.swift`, same pattern
/// as every other network-backed view model test in this repo.
@MainActor
final class CreateChallengeTests: XCTestCase {
    func testCreateChallengeViewModelFlipsIsPremiumRequiredOn403NotPremiumClub() async throws {
        StubURLProtocol.requestHandler = { _ in (403, Data(#"{"error":"not_premium_club"}"#.utf8)) }
        let model = CreateChallengeViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.createChallenge(clubId: "c1", name: "500km bareng", targetType: "distance", targetValue: 500000, deadline: Date())
        XCTAssertTrue(model.isPremiumRequired)
        XCTAssertNil(model.createdChallenge)
        XCTAssertNil(model.errorMessage)
    }

    func testCreateChallengeViewModelSetsErrorMessageWhenAlreadyActive() async throws {
        StubURLProtocol.requestHandler = { _ in
            (409, Data(#"{"error":"This Circle already has an active challenge","code":"challenge_active"}"#.utf8))
        }
        let model = CreateChallengeViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.createChallenge(clubId: "c1", name: "500km bareng", targetType: "distance", targetValue: 500000, deadline: Date())
        XCTAssertFalse(model.isPremiumRequired)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.createdChallenge)
    }

    func testCreateChallengeViewModelSucceedsAndStoresTheCreatedChallenge() async throws {
        StubURLProtocol.requestHandler = { _ in
            (
                201,
                Data(
                    #"{"challenge_id":"ch1","club_id":"c1","name":"500km bareng","target_type":"distance","target_value":500000,"deadline":"2026-10-26T10:00:00Z","status":"active","created_at":"2026-09-26T10:00:00Z"}"#
                        .utf8
                )
            )
        }
        let model = CreateChallengeViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.createChallenge(clubId: "c1", name: "500km bareng", targetType: "distance", targetValue: 500000, deadline: Date())
        XCTAssertFalse(model.isPremiumRequired)
        XCTAssertEqual(model.createdChallenge?.challengeId, "ch1")
        XCTAssertEqual(model.createdChallenge?.status, "active")
    }
}
