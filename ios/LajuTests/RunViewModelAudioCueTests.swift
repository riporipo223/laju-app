import CoreLocation
@testable import Laju
import XCTest

/// T1.13 DoD: an audio cue fires exactly once per km boundary crossed, carries the km number and pace, and
/// GPS jitter around a boundary must not duplicate it — split out from `RunViewModelTests` to keep that file
/// under SwiftLint's type-body-length limit (established pattern this session).
private final class AudioCueSpy: AudioCueAnnouncing {
    private(set) var calls: [(kmNumber: Int, paceSecPerKm: Double)] = []

    func announce(kmNumber: Int, paceSecPerKm: Double) {
        calls.append((kmNumber, paceSecPerKm))
    }
}

final class RunViewModelAudioCueTests: XCTestCase {
    private func makeViewModel(spy: AudioCueAnnouncing) -> (RunViewModel, LocationTrackingService) {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context, audioCueService: spy)
        return (viewModel, locationService)
    }

    func testAnnouncesExactlyOnceWhenAKmBoundaryIsCrossed() {
        let spy = AudioCueSpy()
        let (viewModel, locationService) = makeViewModel(spy: spy)

        viewModel.start()
        // ~1.1km step — clears the 1000m boundary in one update.
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7157, longitude: 110.4084))
        viewModel.stop()

        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls.first?.kmNumber, 1)
    }

    func testDoesNotAnnounceAgainForFurtherMovementWithinTheSameKm() {
        let spy = AudioCueSpy()
        let (viewModel, locationService) = makeViewModel(spy: spy)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7157, longitude: 110.4084)) // closes km 1
        // Small jitter-like updates that stay within the same still-open second km.
        locationService.locationUpdates.send(CLLocation(latitude: -7.7159, longitude: 110.4084))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7161, longitude: 110.4084))
        viewModel.stop()

        XCTAssertEqual(spy.calls.count, 1, "No new boundary was crossed after km 1 — must not re-announce")
    }

    func testAnnouncesAgainOnASecondBoundaryCrossing() {
        let spy = AudioCueSpy()
        let (viewModel, locationService) = makeViewModel(spy: spy)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057, longitude: 110.4084))
        locationService.locationUpdates.send(CLLocation(latitude: -7.7157, longitude: 110.4084)) // closes km 1
        locationService.locationUpdates.send(CLLocation(latitude: -7.7257, longitude: 110.4084)) // closes km 2
        viewModel.stop()

        XCTAssertEqual(spy.calls.count, 2)
        XCTAssertEqual(spy.calls.map(\.kmNumber), [1, 2])
    }
}
