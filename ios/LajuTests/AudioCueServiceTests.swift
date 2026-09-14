@testable import Laju
import XCTest

final class AudioCueServiceTests: XCTestCase {
    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "AudioCueServiceTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        return try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    func testAnnouncementTextContainsKmNumberAndPace() {
        let text = AudioCueService.announcementText(kmNumber: 5, paceSecPerKm: 330)
        XCTAssertTrue(text.contains("5"))
        XCTAssertTrue(text.contains("5 minute"))
        XCTAssertTrue(text.contains("30 second"))
    }

    func testIsEnabledDefaultsToTrueWhenNeverSet() throws {
        let service = try AudioCueService(userDefaults: makeIsolatedDefaults())
        XCTAssertTrue(service.isEnabled)
    }

    func testDisablingSuppressesFutureAnnouncements() throws {
        var spokenTexts: [String] = []
        let service = try AudioCueService(userDefaults: makeIsolatedDefaults()) { spokenTexts.append($0) }

        service.isEnabled = false
        service.announce(kmNumber: 1, paceSecPerKm: 300)

        XCTAssertTrue(spokenTexts.isEmpty)
    }

    func testEnabledAnnouncesThroughTheInjectedSpeakClosure() throws {
        var spokenTexts: [String] = []
        let service = try AudioCueService(userDefaults: makeIsolatedDefaults()) { spokenTexts.append($0) }

        service.announce(kmNumber: 2, paceSecPerKm: 300)

        XCTAssertEqual(spokenTexts.count, 1)
    }
}
