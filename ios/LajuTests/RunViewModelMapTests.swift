import CoreLocation
@testable import Laju
import XCTest

/// T1.8 DoD: live map state (`currentCoordinate`/`routeCoordinates`) must
/// update from the same point-append path as `gpsRoute` itself, freeze
/// while paused, and reset per run — split into its own file to keep
/// `RunViewModelTests` under SwiftLint's type-body-length limit.
final class RunViewModelMapTests: XCTestCase {
    func testCurrentCoordinateAndRouteUpdateAsPointsArrive() {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()
        XCTAssertNil(viewModel.currentCoordinate)
        XCTAssertTrue(viewModel.routeCoordinates.isEmpty)

        let first = CLLocation(latitude: -7.7057000, longitude: 110.4084000)
        locationService.locationUpdates.send(first)
        XCTAssertEqual(viewModel.currentCoordinate?.latitude, first.coordinate.latitude)
        XCTAssertEqual(viewModel.routeCoordinates.count, 1)

        let second = CLLocation(latitude: -7.7066000, longitude: 110.4084000)
        locationService.locationUpdates.send(second)
        XCTAssertEqual(viewModel.currentCoordinate?.latitude, second.coordinate.latitude)
        XCTAssertEqual(
            viewModel.routeCoordinates.count,
            2,
            "Every accepted point must append to the route, matching gpsRoute"
        )

        viewModel.stop()
    }

    func testMapStateFreezesWhilePaused() {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057000, longitude: 110.4084000))
        viewModel.pause()
        let coordinateBeforePause = viewModel.currentCoordinate
        let countBeforePause = viewModel.routeCoordinates.count

        locationService.locationUpdates.send(CLLocation(latitude: -7.7066000, longitude: 110.4084000))
        XCTAssertEqual(viewModel.currentCoordinate?.latitude, coordinateBeforePause?.latitude)
        XCTAssertEqual(viewModel.routeCoordinates.count, countBeforePause, "No new route point while paused")

        viewModel.resume()
        viewModel.stop()
    }

    func testMapStateResetsOnNewRun() {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)

        viewModel.start()
        locationService.locationUpdates.send(CLLocation(latitude: -7.7057000, longitude: 110.4084000))
        viewModel.stop()

        viewModel.start()
        XCTAssertNil(
            viewModel.currentCoordinate,
            "A new run must start with no leftover map state from the previous one"
        )
        XCTAssertTrue(viewModel.routeCoordinates.isEmpty)
        viewModel.stop()
    }

    /// Regression test for a real bug found on-device (2026-09-13): a
    /// second run started shortly after a first one, without moving in
    /// between, never got its first map fix — every fix was rejected by
    /// `LocationTrackingService`'s own jitter floor against the FIRST
    /// run's last accepted position (same spot, so every step reads as
    /// noise). Goes through the real delegate callback (not the
    /// `locationUpdates` subject directly) since the bug lives inside
    /// `LocationTrackingService`'s own filtering, which injecting
    /// straight into the subject would bypass entirely.
    func testSamePositionIsAcceptedAgainInANewRunAfterAPreviousOne() {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let locationService = LocationTrackingService()
        let viewModel = RunViewModel(locationService: locationService, context: context)
        let manager = CLLocationManager() // unused by the delegate method's body, any instance works

        func fixAtSameSpot() -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: -7.7057000, longitude: 110.4084000),
                altitude: 0,
                horizontalAccuracy: 7,
                verticalAccuracy: 5,
                timestamp: Date()
            )
        }

        viewModel.start()
        locationService.locationManager(manager, didUpdateLocations: [fixAtSameSpot()])
        XCTAssertNotNil(viewModel.currentCoordinate, "First run's fix must be accepted (no prior state to reject it)")
        viewModel.stop()

        viewModel.start()
        locationService.locationManager(manager, didUpdateLocations: [fixAtSameSpot()])
        XCTAssertNotNil(
            viewModel.currentCoordinate,
            "A second run's fix at the SAME position must still be accepted — resetSessionFilterState() must clear " +
                "the previous run's jitter-floor reference, or the map never gets its first fix"
        )
        viewModel.stop()
    }
}
