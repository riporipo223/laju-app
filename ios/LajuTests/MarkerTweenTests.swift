import CoreLocation
@testable import Laju
import XCTest

/// The smooth-movement layer is display-only, so what needs proving is (1) the interpolation math itself and
/// (2) that it stays out of the way: bounded lag, snap on big jumps. That the recorded route, distance, pace and
/// points are unchanged is proven by the existing suites (`RunViewModel*`, `GPSFilter*`, point/distance tests)
/// still passing untouched — none of them reference this file.
final class MarkerTweenTests: XCTestCase {
    private let origin = CLLocationCoordinate2D(latitude: -6.2000, longitude: 106.8000)
    private let target = CLLocationCoordinate2D(latitude: -6.2002, longitude: 106.8004)

    private func tween(duration: TimeInterval = 0.8) -> MarkerTween {
        MarkerTween(from: origin, to: target, startTime: 10, duration: duration)
    }

    private func point(_ latitude: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: 106.8)
    }

    func testStartsAtOriginAndEndsExactlyAtTarget() {
        let motion = tween()
        XCTAssertEqual(motion.coordinate(at: 10).latitude, origin.latitude, accuracy: 1e-12)
        XCTAssertEqual(motion.coordinate(at: 10.8).latitude, target.latitude, accuracy: 1e-12)
        XCTAssertEqual(motion.coordinate(at: 10.8).longitude, target.longitude, accuracy: 1e-12)
    }

    func testMidpointIsLinear() {
        let midpoint = tween().coordinate(at: 10.4)
        XCTAssertEqual(midpoint.latitude, (origin.latitude + target.latitude) / 2, accuracy: 1e-12)
        XCTAssertEqual(midpoint.longitude, (origin.longitude + target.longitude) / 2, accuracy: 1e-12)
    }

    func testClampsOutsideTheWindowSoTheMarkerNeverOvershoots() {
        let motion = tween()
        XCTAssertEqual(motion.coordinate(at: 5).latitude, origin.latitude, accuracy: 1e-12)
        XCTAssertEqual(motion.coordinate(at: 99).latitude, target.latitude, accuracy: 1e-12)
        XCTAssertFalse(motion.isFinished(at: 10.79))
        XCTAssertTrue(motion.isFinished(at: 10.8))
    }

    func testZeroDurationIsInstant() {
        let motion = tween(duration: 0)
        XCTAssertTrue(motion.isFinished(at: 10))
        XCTAssertEqual(motion.coordinate(at: 10).latitude, target.latitude, accuracy: 1e-12)
    }

    /// Bounded lag: the glide is never longer than the cap, however slow the GPS updates arrive.
    func testDurationFollowsTheFixIntervalWithinBounds() {
        XCTAssertEqual(MarkerTween.duration(sinceLastFix: 0.05), MarkerTween.minimumDuration)
        XCTAssertEqual(MarkerTween.duration(sinceLastFix: 0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(MarkerTween.duration(sinceLastFix: 1.0), MarkerTween.maximumDuration)
        XCTAssertEqual(MarkerTween.duration(sinceLastFix: 30), MarkerTween.maximumDuration)
        XCTAssertEqual(MarkerTween.duration(sinceLastFix: nil), MarkerTween.maximumDuration)
        XCTAssertLessThanOrEqual(MarkerTween.maximumDuration, 1.0)
    }

    func testSnapsOnLargeJumpsButGlidesOnNormalRunningSteps() {
        XCTAssertFalse(MarkerTween.shouldSnap(from: point(-6.2000), to: point(-6.20004))) // ~4 m
        XCTAssertFalse(MarkerTween.shouldSnap(from: point(-6.2000), to: point(-6.2002))) // ~22 m
        XCTAssertTrue(MarkerTween.shouldSnap(from: point(-6.2000), to: point(-6.2020))) // ~222 m: resume/first fix
    }

    /// A fix arriving mid-glide must continue from where the marker is, not from the old target.
    func testRetargetingMidGlideStartsFromTheDisplayedPosition() {
        let displayed = tween().coordinate(at: 10.4)
        let next = CLLocationCoordinate2D(latitude: -6.2004, longitude: 106.8008)
        let second = MarkerTween(from: displayed, to: next, startTime: 10.4, duration: 0.5)
        XCTAssertEqual(second.coordinate(at: 10.4).latitude, displayed.latitude, accuracy: 1e-12)
        XCTAssertEqual(second.coordinate(at: 10.9).latitude, next.latitude, accuracy: 1e-12)
    }

    func testTailOverlayReportsWhatWasSet() {
        let tail = TailOverlay()
        tail.update(anchor: origin, head: target)
        XCTAssertEqual(tail.segment().anchor.latitude, origin.latitude)
        XCTAssertEqual(tail.segment().head.longitude, target.longitude)
        tail.update(head: origin) // a head-only update must keep the anchor
        XCTAssertEqual(tail.segment().anchor.latitude, origin.latitude)
        XCTAssertEqual(tail.segment().head.latitude, origin.latitude)
    }
}
