@testable import Laju
import XCTest

/// T1.3 DoD: `levelThresholds` must match database-api-spec.md §1
/// exactly, row for row, and `currentLevel`/`pointsToNextLevel` must
/// derive correctly at every boundary.
final class LevelProgressionTests: XCTestCase {
    func testLevelThresholdsMatchDatabaseApiSpecExactly() {
        let expected: [LevelThreshold] = [
            LevelThreshold(level: 1, pointsRequired: 0, title: "Pemula"),
            LevelThreshold(level: 2, pointsRequired: 100, title: "Rajin"),
            LevelThreshold(level: 3, pointsRequired: 300, title: "Konsisten"),
            LevelThreshold(level: 4, pointsRequired: 700, title: "Gigih"),
            LevelThreshold(level: 5, pointsRequired: 1500, title: "Veteran"),
            LevelThreshold(level: 6, pointsRequired: 3000, title: "Elit"),
            LevelThreshold(level: 7, pointsRequired: 6000, title: "Master"),
            LevelThreshold(level: 8, pointsRequired: 12000, title: "Legenda")
        ]

        XCTAssertEqual(LevelProgression.levelThresholds, expected)
    }

    func testCurrentLevelBoundaries() {
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 0).level, 1)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 99).level, 1)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 100).level, 2)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 299).level, 2)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 300).level, 3)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 699).level, 3)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 700).level, 4)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 1499).level, 4)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 1500).level, 5)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 2999).level, 5)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 3000).level, 6)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 5999).level, 6)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 6000).level, 7)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 11999).level, 7)
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 12000).level, 8)
    }

    func testTopLevelHasNoCapBeyondLevelEight() {
        // database-api-spec.md §1: no level cap defined beyond 8 — a
        // total past 12000 just stays at level 8, pointsToNextLevel 0.
        XCTAssertEqual(LevelProgression.currentLevel(totalPoints: 999_999).level, 8)
        XCTAssertEqual(LevelProgression.pointsToNextLevel(totalPoints: 999_999), 0)
        XCTAssertEqual(LevelProgression.pointsToNextLevel(totalPoints: 12000), 0)
    }

    func testPointsToNextLevel() {
        XCTAssertEqual(LevelProgression.pointsToNextLevel(totalPoints: 0), 100)
        XCTAssertEqual(LevelProgression.pointsToNextLevel(totalPoints: 50), 50)
        XCTAssertEqual(LevelProgression.pointsToNextLevel(totalPoints: 100), 200)
        XCTAssertEqual(LevelProgression.pointsToNextLevel(totalPoints: 6000), 6000)
    }
}
