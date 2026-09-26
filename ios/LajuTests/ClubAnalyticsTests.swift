@testable import Laju
import XCTest

/// product-spec.md §4.24 AC12: `ClubAnalyticsViewModel`'s Premium-gate detection and success path.
@MainActor
final class ClubAnalyticsTests: XCTestCase {
    func testLoadFlipsIsPremiumRequiredOn403NotPremiumClub() async throws {
        StubURLProtocol.requestHandler = { _ in (403, Data(#"{"error":"not_premium_club"}"#.utf8)) }
        let model = ClubAnalyticsViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.load(clubId: "c1")
        XCTAssertTrue(model.isPremiumRequired)
        XCTAssertNil(model.analytics)
    }

    func testLoadPopulatesAnalytics() async throws {
        StubURLProtocol.requestHandler = { _ in
            (
                200,
                Data(
                    #"{"total_distance_meters":120000,"total_points":240,"active_member_count":3,"top_contributors":[{"user_id":"usr-1","distance_meters":90000,"points":180}]}"#
                        .utf8
                )
            )
        }
        let model = ClubAnalyticsViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.load(clubId: "c1")
        XCTAssertFalse(model.isPremiumRequired)
        XCTAssertEqual(model.analytics?.totalDistanceMeters, 120000)
        XCTAssertEqual(model.analytics?.activeMemberCount, 3)
        XCTAssertEqual(model.analytics?.topContributors.first?.userId, "usr-1")
    }
}
