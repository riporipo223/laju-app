@testable import Laju
import XCTest

/// T4.1: `CreateClubViewModel`'s DTO encoding and network behavior. Reuses `StubURLProtocol` from
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
        XCTAssertEqual(model.createdClub?.clubId, "c1")
    }

    func testCreateClubViewModelSetsErrorMessageWhenAlreadyInAClub() async throws {
        StubURLProtocol.requestHandler = { _ in (409, Data(#"{"error":"You are already in a club"}"#.utf8)) }
        let model = CreateClubViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.createClub(name: "Lari Pagi", description: nil, privacy: "public")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.createdClub)
    }
}
