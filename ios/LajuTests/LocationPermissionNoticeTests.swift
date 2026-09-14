import CoreLocation
@testable import Laju
import XCTest

/// T1.15 DoD: all 3 authorization states must produce visibly distinct copy — verified here at the pure
/// enum level rather than only visually, since the copy itself is what the DoD requires to differ.
final class LocationPermissionNoticeTests: XCTestCase {
    func testAuthorizedAlwaysHasNoNotice() {
        XCTAssertNil(LocationPermissionNotice.notice(for: .authorizedAlways))
    }

    func testNotDeterminedHasNoPersistentNotice() {
        XCTAssertNil(LocationPermissionNotice.notice(for: .notDetermined))
    }

    func testAuthorizedWhenInUseProducesDistinctWhileUsingNotice() {
        XCTAssertEqual(LocationPermissionNotice.notice(for: .authorizedWhenInUse), .whileUsingOnly)
    }

    func testDeniedAndRestrictedBothProduceTheDeniedNotice() {
        XCTAssertEqual(LocationPermissionNotice.notice(for: .denied), .denied)
        XCTAssertEqual(LocationPermissionNotice.notice(for: .restricted), .denied)
    }

    func testWhileUsingCopyExplicitlyWarnsAboutBackgroundTrackingLimitation() {
        let notice = LocationPermissionNotice.whileUsingOnly
        XCTAssertTrue(notice.message.localizedCaseInsensitiveContains("background") || notice.message
            .contains("kunci layar"))
    }

    func testTheTwoNoticesHaveDifferentCopy() {
        XCTAssertNotEqual(LocationPermissionNotice.whileUsingOnly.title, LocationPermissionNotice.denied.title)
        XCTAssertNotEqual(LocationPermissionNotice.whileUsingOnly.message, LocationPermissionNotice.denied.message)
    }
}
