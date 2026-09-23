import CoreLocation
@testable import Laju
import XCTest

/// Task C (2026-09-22, product-spec.md §4.5 AC5): `LeaderboardAccessState.state(for:)` decides how the
/// Leaderboard tab presents itself for every `CLAuthorizationStatus` — closes a real PR-checklist gap
/// (repo-coding-rules.md §4 "new/changed logic has at least one test") found during the merge review for
/// `LocationAuthorizationObserver.swift`/`LeaderboardLockedView.swift`, which shipped with zero coverage.
/// Same pattern as `LocationPermissionNoticeTests.swift` (T1.15): verify the pure enum mapping directly
/// rather than only visually, since the mapping itself is what AC5 requires to be correct.
final class LocationAuthorizationObserverTests: XCTestCase {
    func testAuthorizedStatesUnlockTheLeaderboard() {
        XCTAssertEqual(LeaderboardAccessState.state(for: .authorizedAlways), .unlocked)
        XCTAssertEqual(LeaderboardAccessState.state(for: .authorizedWhenInUse), .unlocked)
    }

    func testNotDeterminedAsksRatherThanLocksOrDenies() {
        // AC5 does not specify this split; the implementation's own doc comment flags it as a decision
        // made here, not confirmed — this test pins that decision so a future change to it is deliberate.
        XCTAssertEqual(LeaderboardAccessState.state(for: .notDetermined), .needsPermission)
    }

    func testDeniedLocksWithNoWayToRequestAgain() {
        XCTAssertEqual(LeaderboardAccessState.state(for: .denied), .denied)
    }

    func testRestrictedGetsItsOwnStateNotTreatedAsPlainDenied() {
        // Distinct from `.denied` on purpose: a restricted user (parental controls/MDM) cannot grant
        // permission at all, so a Settings CTA would be a dead end — the view needs to tell them apart.
        XCTAssertEqual(LeaderboardAccessState.state(for: .restricted), .restricted)
    }

    func testEveryKnownCaseIsHandledExplicitlyNotByTheDefaultBranch() {
        // `state(for:)`'s switch has an explicit case for every value except the always-denied default —
        // this just confirms the four cases above are exhaustive over CLAuthorizationStatus as it exists
        // today, so a future new case doesn't silently fall through this test suite unnoticed.
        let allCases: [CLAuthorizationStatus] = [
            .authorizedAlways, .authorizedWhenInUse, .notDetermined, .restricted, .denied
        ]
        let states = allCases.map(LeaderboardAccessState.state(for:))
        XCTAssertEqual(states, [.unlocked, .unlocked, .needsPermission, .restricted, .denied])
    }
}
