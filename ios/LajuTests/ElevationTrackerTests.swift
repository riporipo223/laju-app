@testable import Laju
import XCTest

final class ElevationTrackerTests: XCTestCase {
    private func point(_ elevation: Double, secondsOffset: Double) -> GPSPoint {
        GPSPoint(lat: 0, lng: 0, timestamp: Date(timeIntervalSince1970: secondsOffset), elevation: elevation)
    }

    func testNoPointsProducesZeroGainAndLoss() {
        let result = ElevationTracker.compute(points: [])
        XCTAssertEqual(result.gainMeters, 0)
        XCTAssertEqual(result.lossMeters, 0)
    }

    func testSteadyClimbAccumulatesGainWithNoLoss() {
        let points = [point(100, secondsOffset: 0), point(110, secondsOffset: 10), point(120, secondsOffset: 20)]
        let result = ElevationTracker.compute(points: points)
        XCTAssertEqual(result.gainMeters, 20, accuracy: 0.001)
        XCTAssertEqual(result.lossMeters, 0)
    }

    func testDescentThenClimbAccumulatesBothSeparately() {
        let points = [point(150, secondsOffset: 0), point(120, secondsOffset: 10), point(140, secondsOffset: 20)]
        let result = ElevationTracker.compute(points: points)
        XCTAssertEqual(result.gainMeters, 20, accuracy: 0.001)
        XCTAssertEqual(result.lossMeters, 30, accuracy: 0.001)
    }

    /// T1.12 DoD: a flat-but-noisy route (small random jitter, no real elevation change) must not produce a
    /// materially inflated gain/loss number — every jitter step here is under `noiseFloorMeters` (3m).
    func testFlatNoisyRouteProducesNegligibleGainAndLoss() {
        let jitters: [Double] = [0, 1.2, -0.8, 1.5, -1.9, 0.4, -0.3, 1.8, -1.1, 0.6]
        let points = jitters.enumerated().map { index, jitter in
            point(100 + jitter, secondsOffset: Double(index) * 5)
        }
        let result = ElevationTracker.compute(points: points)
        XCTAssertEqual(result.gainMeters, 0)
        XCTAssertEqual(result.lossMeters, 0)
    }

    /// A real climb riding on top of sub-floor jitter must still register — noise filtering shouldn't also
    /// eat genuine elevation change once it clears the floor.
    func testRealClimbSurvivesSmallJitterOnTop() {
        let points = [
            point(100, secondsOffset: 0),
            point(100.5, secondsOffset: 5), // jitter, under floor
            point(106, secondsOffset: 10), // real climb, over floor
            point(106.4, secondsOffset: 15) // jitter, under floor from new reference
        ]
        let result = ElevationTracker.compute(points: points)
        XCTAssertEqual(result.gainMeters, 6, accuracy: 0.001)
        XCTAssertEqual(result.lossMeters, 0)
    }
}
