@testable import Laju
import XCTest

/// product-spec.md §4.29 AC1-AC3: client-side replica of the backend's severe-speed-violation rule
/// (`severe-speed-violation.ts`) — same threshold (25 km/h), same 5-consecutive/2-minute-window
/// shape, same reset-on-clean-sample behavior. Advisory only (ADR-0008) — this file never decides
/// points/penalties, only whether to show a live warning banner.
final class SevereSpeedViolationDetectorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    func testDoesNotTriggerOnFewerThanFiveConsecutiveDetections() {
        let detector = SevereSpeedViolationDetector()
        for i in 0..<4 {
            detector.record(speedKmh: 30, at: start.addingTimeInterval(Double(i) * 10))
        }
        XCTAssertFalse(detector.isTriggered)
    }

    func testTriggersOnExactlyFiveConsecutiveDetectionsWithinTheWindow() {
        let detector = SevereSpeedViolationDetector()
        for i in 0..<5 {
            detector.record(speedKmh: 30, at: start.addingTimeInterval(Double(i) * 10))
        }
        XCTAssertTrue(detector.isTriggered)
    }

    func testResetsTheStreakOnACleanSample() {
        let detector = SevereSpeedViolationDetector()
        for i in 0..<3 {
            detector.record(speedKmh: 30, at: start.addingTimeInterval(Double(i) * 10))
        }
        detector.record(speedKmh: 12, at: start.addingTimeInterval(30)) // clean sample, under cap
        for i in 0..<3 {
            detector.record(speedKmh: 30, at: start.addingTimeInterval(40 + Double(i) * 10))
        }
        XCTAssertFalse(detector.isTriggered) // only 3 after the reset, never reached 5 in a row
    }

    func testFreshStreakAfterAResetCanStillTrigger() {
        let detector = SevereSpeedViolationDetector()
        for i in 0..<4 {
            detector.record(speedKmh: 30, at: start.addingTimeInterval(Double(i) * 10))
        }
        detector.record(speedKmh: 12, at: start.addingTimeInterval(40)) // reset
        for i in 0..<5 {
            detector.record(speedKmh: 30, at: start.addingTimeInterval(50 + Double(i) * 10))
        }
        XCTAssertTrue(detector.isTriggered)
    }

    func testDoesNotTriggerWhenFiveConsecutiveDetectionsSpanMoreThanTwoMinutes() {
        let detector = SevereSpeedViolationDetector()
        for i in 0..<5 {
            detector.record(speedKmh: 30, at: start.addingTimeInterval(Double(i) * 40)) // 160s total span
        }
        XCTAssertFalse(detector.isTriggered)
    }

    func testResetClearsTheTriggeredFlagAndTheStreak() {
        let detector = SevereSpeedViolationDetector()
        for i in 0..<5 {
            detector.record(speedKmh: 30, at: start.addingTimeInterval(Double(i) * 10))
        }
        XCTAssertTrue(detector.isTriggered)
        detector.reset()
        XCTAssertFalse(detector.isTriggered)
    }
}
