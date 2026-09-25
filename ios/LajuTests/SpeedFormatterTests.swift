@testable import Laju
import XCTest

/// GPS/speed audit (2026-09-25, v1 decision): user-facing display replaces pace with speed (km/h)
/// everywhere. No formatter test existed for `PaceFormatter` either — this is the first for either,
/// added alongside the new one since `SpeedFormatter`'s conversion math (`3600 / secPerKm`) is easy to
/// get backwards (km/h vs h/km) without a test catching it.
final class SpeedFormatterTests: XCTestCase {
    func testConvertsSixMinutePaceToTenKmh() {
        // 6:00 /km == 360 sec/km == 3600/360 = 10.0 km/h — a clean round-trip number, easy to eyeball.
        XCTAssertEqual(SpeedFormatter.format(secPerKm: 360), "10.0 km/h")
    }

    func testConvertsFiveMinutePaceToTwelveKmh() {
        XCTAssertEqual(SpeedFormatter.format(secPerKm: 300), "12.0 km/h")
    }

    func testZeroSecPerKmReturnsZeroKmhNotDivideByZero() {
        XCTAssertEqual(SpeedFormatter.format(secPerKm: 0), "0.0 km/h")
    }

    func testRoundsToOneDecimalPlace() {
        // 6:15 /km == 375 sec/km == 3600/375 = 9.6 km/h
        XCTAssertEqual(SpeedFormatter.format(secPerKm: 375), "9.6 km/h")
    }
}
