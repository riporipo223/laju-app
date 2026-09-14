@testable import Laju
import XCTest

/// T1.1 DoD: pace bracket boundaries, streak cap, zero-distance, and
/// fixture parity against `shared/point-formula.fixtures.json` (the
/// cross-language parity mechanism, tech-spec.md §2.2b).
final class PointFormulaTests: XCTestCase {
    func testPaceBracketBoundaries() {
        // Half-open brackets: the upper bound itself belongs to the NEXT
        // bracket, not the current one (tech-spec.md §2.3).
        XCTAssertEqual(PointFormula.paceMultiplier(avgPaceSecPerKm: 179), 0.5)
        XCTAssertEqual(PointFormula.paceMultiplier(avgPaceSecPerKm: 180), 1.2)
        XCTAssertEqual(PointFormula.paceMultiplier(avgPaceSecPerKm: 239), 1.2)
        XCTAssertEqual(PointFormula.paceMultiplier(avgPaceSecPerKm: 240), 1.0)
        XCTAssertEqual(PointFormula.paceMultiplier(avgPaceSecPerKm: 419), 1.0)
        XCTAssertEqual(PointFormula.paceMultiplier(avgPaceSecPerKm: 420), 0.9)
        XCTAssertEqual(PointFormula.paceMultiplier(avgPaceSecPerKm: 599), 0.9)
        XCTAssertEqual(PointFormula.paceMultiplier(avgPaceSecPerKm: 600), 0.7)
    }

    func testStreakBonusCapsAtSevenDays() {
        let atCap = PointFormula.calculatePoints(distanceKm: 5, avgPaceSecPerKm: 300, streakDays: 7)
        let beyondCap = PointFormula.calculatePoints(distanceKm: 5, avgPaceSecPerKm: 300, streakDays: 8)
        XCTAssertEqual(atCap, beyondCap, "Streak bonus must cap at 7 days, per tech-spec.md §2.2")
        XCTAssertEqual(atCap, 5.0 + 7 * PointFormula.streakBonusPerDay, accuracy: 0.0001)
    }

    func testZeroDistanceEdgeCase() {
        let points = PointFormula.calculatePoints(distanceKm: 0, avgPaceSecPerKm: 300, streakDays: 0)
        XCTAssertEqual(points, 0, accuracy: 0.0001)
    }

    /// Regression test for a real grinding exploit found on-device
    /// (2026-09-13): tap Start then Stop immediately (distanceKm≈0) with
    /// an existing streak still earned the full streak bonus, since
    /// `streakBonus` is additive against `basePoints`, not multiplicative
    /// — confirmed on-device as 6.0/8.0 points from `distanceMeters=0`
    /// runs at streak_days 3/4. Exact scenario: near-zero distance, max
    /// streak (7 days, the most a grinder could exploit per run) must
    /// still yield 0 total, not just 0 base points.
    func testZeroDistanceWithMaxStreakYieldsZeroNotJustBasePoints() {
        let points = PointFormula.calculatePoints(distanceKm: 0, avgPaceSecPerKm: 300, streakDays: 7)
        XCTAssertEqual(points, 0, accuracy: 0.0001, "A 0-distance run must not earn any points, streak bonus included")
    }

    func testBelowMinimumDistanceGatesTotalPointsToZeroRegardlessOfStreak() {
        let justBelow = PointFormula.calculatePoints(
            distanceKm: PointFormula.minDistanceKmForPoints - 0.001,
            avgPaceSecPerKm: 300,
            streakDays: 7
        )
        XCTAssertEqual(justBelow, 0, accuracy: 0.0001)
    }

    func testAtMinimumDistanceGateIsInclusiveAndAwardsPointsNormally() {
        let atThreshold = PointFormula.calculatePoints(
            distanceKm: PointFormula.minDistanceKmForPoints,
            avgPaceSecPerKm: 300,
            streakDays: 0
        )
        XCTAssertGreaterThan(atThreshold, 0, "The gate is inclusive (>=) — exactly at the threshold must award points")
    }

    func testFixtureParity() throws {
        let fixtures = try loadFixtures()
        // Row-count assertion so an accidentally-reverted (emptied)
        // fixture file fails loudly instead of silently passing with
        // zero assertions run.
        XCTAssertGreaterThan(fixtures.count, 0, "point-formula.fixtures.json must not be empty")

        for (index, fixture) in fixtures.enumerated() {
            let actual = PointFormula.calculatePoints(
                distanceKm: fixture.input.distanceKm,
                avgPaceSecPerKm: fixture.input.avgPaceSecPerKm,
                streakDays: fixture.input.streakDays
            )
            XCTAssertEqual(
                actual,
                fixture.expectedPoints,
                accuracy: 0.0001,
                "Fixture row \(index) (\(fixture.input)) expected \(fixture.expectedPoints), got \(actual)"
            )
        }
    }

    // MARK: - Fixture loading

    /// `shared/point-formula.fixtures.json` lives at the repo root, not
    /// inside `ios/` — rather than fight Xcode resource bundling for a
    /// file outside the target's source tree, resolve it relative to
    /// this test file's own compile-time path (`#filePath`), which is
    /// correct both locally and in CI (compilation and test execution
    /// happen on the same filesystem in the same job).
    private func loadFixtures() throws -> [Fixture] {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // PointFormulaTests.swift -> LajuTests/
            .deletingLastPathComponent() // LajuTests/ -> ios/
            .deletingLastPathComponent() // ios/ -> repo root
        let fixturesURL = repoRoot.appendingPathComponent("shared/point-formula.fixtures.json")
        let data = try Data(contentsOf: fixturesURL)
        return try JSONDecoder().decode([Fixture].self, from: data)
    }
}

private struct FixtureInput: Decodable, CustomStringConvertible {
    let distanceKm: Double
    let avgPaceSecPerKm: Double
    let streakDays: Int

    enum CodingKeys: String, CodingKey {
        case distanceKm = "distance_km"
        case avgPaceSecPerKm = "avg_pace_sec_per_km"
        case streakDays = "streak_days"
    }

    var description: String {
        "distanceKm=\(distanceKm) avgPaceSecPerKm=\(avgPaceSecPerKm) streakDays=\(streakDays)"
    }
}

private struct Fixture: Decodable {
    let input: FixtureInput
    let expectedPoints: Double

    enum CodingKeys: String, CodingKey {
        case input
        case expectedPoints = "expected_points"
    }
}
