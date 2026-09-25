@testable import Laju
import XCTest

/// T4.1: `CreateClubViewModel`'s Premium-gate detection and DTO encoding. Reuses `StubURLProtocol` from
/// `SyncServiceTests.swift`, same pattern as every other network-backed view model test in this repo.
@MainActor
final class CreateClubTests: XCTestCase {
    func testCreateClubRequestEncodesNameDescriptionAndPrivacy() throws {
        let body = try RunSubmissionCoding.makeEncoder().encode(
            CreateClubRequest(name: "Lari Pagi", description: "Komunitas lari", privacy: "invite_only")
        )
        let decoded = try JSONDecoder().decode(CreateClubRequest.self, from: body)
        XCTAssertEqual(decoded.name, "Lari Pagi")
        XCTAssertEqual(decoded.description, "Komunitas lari")
        XCTAssertEqual(decoded.privacy, "invite_only")
    }

    func testCreateClubViewModelFlipsIsPremiumRequiredOn403NotPremium() async throws {
        StubURLProtocol.requestHandler = { _ in
            (403, Data(#"{"error":"Creating a club requires Premium","code":"not_premium"}"#.utf8))
        }
        let model = CreateClubViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.createClub(name: "Lari Pagi", description: nil, privacy: "public")
        XCTAssertTrue(model.isPremiumRequired)
        XCTAssertNil(model.createdClub)
        XCTAssertNil(model.errorMessage) // premium-required is its own state, not a generic error
    }

    func testCreateClubViewModelSucceedsAndStoresTheCreatedClub() async throws {
        StubURLProtocol.requestHandler = { _ in
            (
                201,
                Data(
                    #"{"club_id":"c1","name":"Lari Pagi","description":null,"privacy":"public","invite_code":null,"created_at":"2026-09-25T10:00:00Z"}"#
                        .utf8
                )
            )
        }
        let model = CreateClubViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.createClub(name: "Lari Pagi", description: nil, privacy: "public")
        XCTAssertFalse(model.isPremiumRequired)
        XCTAssertEqual(model.createdClub?.clubId, "c1")
    }

    func testCreateClubViewModelSetsErrorMessageWhenAlreadyInAClub() async throws {
        StubURLProtocol.requestHandler = { _ in (409, Data(#"{"error":"You are already in a club"}"#.utf8)) }
        let model = CreateClubViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.createClub(name: "Lari Pagi", description: nil, privacy: "public")
        XCTAssertFalse(model.isPremiumRequired)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.createdClub)
    }
}
