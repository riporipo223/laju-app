@testable import Laju
import XCTest

/// T1.11 DoD: pure threshold logic backing the auto-pause watchdog — verified in isolation, no timer needed.
final class AutoPauseThresholdTests: XCTestCase {
    func testNotExceededWhenNoAnchorHasEverBeenConfirmed() {
        XCTAssertFalse(AutoPauseThreshold.isExceeded(lastConfirmedMovementAt: nil))
    }

    func testNotExceededBeforeTheThresholdElapses() {
        let now = Date()
        let lastMovement = now.addingTimeInterval(-30)
        XCTAssertFalse(AutoPauseThreshold.isExceeded(
            lastConfirmedMovementAt: lastMovement,
            now: now,
            thresholdSeconds: 60
        ))
    }

    func testExceededExactlyAtTheThreshold() {
        let now = Date()
        let lastMovement = now.addingTimeInterval(-60)
        XCTAssertTrue(AutoPauseThreshold.isExceeded(
            lastConfirmedMovementAt: lastMovement,
            now: now,
            thresholdSeconds: 60
        ))
    }

    func testExceededWellPastTheThreshold() {
        let now = Date()
        let lastMovement = now.addingTimeInterval(-120)
        XCTAssertTrue(AutoPauseThreshold.isExceeded(
            lastConfirmedMovementAt: lastMovement,
            now: now,
            thresholdSeconds: 60
        ))
    }
}
