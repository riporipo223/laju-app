@testable import Laju
import XCTest

/// CQ-11 (code-quality-audit.md): reproduces the reported jumpiness with synthetic GPS-derived
/// movement samples, then proves the rolling-window fix measurably reduces it against the SAME
/// input the old whole-run cumulative average formula would have used.
final class RollingSpeedCalculatorTests: XCTestCase {
    /// The OLD, buggy formula this fix replaces — `liveActiveDuration() / (distanceMeters / 1000)`,
    /// literally reimplemented here (not imported — it no longer exists in production code after this
    /// fix) purely so this test can demonstrate the improvement against the same inputs.
    private func oldCumulativePaceSecPerKm(runStartedAt: Date, cumulativeDistanceMeters: Double, now: Date) -> Double? {
        guard cumulativeDistanceMeters > 0 else { return nil }
        return now.timeIntervalSince(runStartedAt) / (cumulativeDistanceMeters / 1000)
    }

    /// Reproduces the real mechanism CQ-11 identified: the stationary anchor takes a few seconds to
    /// settle before the FIRST confirmed-movement chunk is accepted, but the old formula's
    /// denominator is time-since-RUN-START, not time-since-first-movement — so that dead time gets
    /// misattributed as "very slow pace" until enough real movement dilutes it away. True pace
    /// throughout this synthetic sequence is a constant 10 km/h (360 sec/km) — a real runner holding
    /// steady effort — the jump is purely an artifact of the old formula, not the runner's actual pace.
    func testRollingWindowHasLowerVarianceThanCumulativeAverageOnASlowFirstFix() throws {
        let runStartedAt = Date(timeIntervalSince1970: 0)
        // First confirmed movement only lands at t=10s (anchor settling) — 10 steady 5s/13.889m
        // steps after that (10 km/h) for 60 more seconds.
        var samples: [RollingSpeedCalculator.MovementSample] = []
        var cumulativeDistance = 0.0
        var oldSeries: [Double] = []
        var newSeries: [Double] = []

        let stepTimes = stride(from: 10.0, through: 70.0, by: 5.0)
        for t in stepTimes {
            let now = runStartedAt.addingTimeInterval(t)
            let incrementalDistance = 13.888_9 // 10 km/h over 5s
            cumulativeDistance += incrementalDistance
            samples.append(RollingSpeedCalculator.MovementSample(timestamp: now, distanceMeters: incrementalDistance))

            if let old = oldCumulativePaceSecPerKm(runStartedAt: runStartedAt, cumulativeDistanceMeters: cumulativeDistance, now: now) {
                oldSeries.append(old)
            }
            if let new = RollingSpeedCalculator.rollingPaceSecPerKm(samples: samples, now: now) {
                newSeries.append(new)
            }
        }

        // The old series' first reading is wildly off true pace (dead anchor-settling time counted
        // as if it were slow running) — this is the bug, reproduced.
        XCTAssertGreaterThan(oldSeries.first!, 700) // true pace is 360 sec/km; old is way over 2x that

        // The new series only starts once it has ≥2 samples and enough elapsed span — later than the
        // old series starts, but every value it DOES produce stays much closer to true pace.
        XCTAssertFalse(newSeries.isEmpty)
        for value in newSeries {
            XCTAssertLessThan(abs(value - 360), 60, "rolling window value \(value) strayed further than 60s/km from true pace")
        }

        XCTAssertLessThan(variance(newSeries), variance(oldSeries), "rolling window must have lower variance than the cumulative average it replaces")
    }

    func testReturnsNilWithFewerThanTwoSamples() throws {
        let now = Date()
        let result = RollingSpeedCalculator.rollingPaceSecPerKm(
            samples: [RollingSpeedCalculator.MovementSample(timestamp: now, distanceMeters: 10)],
            now: now
        )
        XCTAssertNil(result)
    }

    func testReturnsNilWhenTheWindowSpanIsTooShortToDivideSafely() throws {
        let now = Date()
        let samples = [
            RollingSpeedCalculator.MovementSample(timestamp: now.addingTimeInterval(-1), distanceMeters: 5),
            RollingSpeedCalculator.MovementSample(timestamp: now, distanceMeters: 5),
        ]
        XCTAssertNil(RollingSpeedCalculator.rollingPaceSecPerKm(samples: samples, now: now))
    }

    func testExcludesSamplesOlderThanTheWindow() throws {
        let now = Date()
        let samples = [
            RollingSpeedCalculator.MovementSample(timestamp: now.addingTimeInterval(-100), distanceMeters: 1000), // outside a 30s window
            RollingSpeedCalculator.MovementSample(timestamp: now.addingTimeInterval(-10), distanceMeters: 50),
            RollingSpeedCalculator.MovementSample(timestamp: now, distanceMeters: 50),
        ]
        let result = try XCTUnwrap(RollingSpeedCalculator.rollingPaceSecPerKm(samples: samples, windowSeconds: 30, now: now))
        // Only the last two samples should be in the window at all (the far-outside 1000m sample
        // must not leak in). Of those two, only the NEWER one's distance (50m) counts — the older
        // one's distance was covered before its own timestamp, outside this window's span. Elapsed
        // is 10s (from the older sample's timestamp to now), so pace = 10s / 0.05km = 200 sec/km.
        XCTAssertEqual(result, 200, accuracy: 0.01)
    }

    private func variance(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }
}
