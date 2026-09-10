import Combine
import CoreLocation

/// Wraps `CLLocationManager` for T0.7/T0.9 — native background GPS
/// tracking, no third-party library (tech-spec.md §1 GPS tracking row).
/// Only this service talks to `CLLocationManager` (architecture.md §3 —
/// Data/Sync layer is the only layer allowed to touch it).
final class LocationTrackingService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isTracking = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastLocation: CLLocation?

    /// Emits each new location while tracking is active — consumed by
    /// `RunViewModel` (T0.8) to append points to the active `Run`.
    let locationUpdates = PassthroughSubject<CLLocation, Never>()

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // meters — throttles redundant updates, tech-spec.md §4
        manager.allowsBackgroundLocationUpdates = false // enabled only once tracking starts (see startTracking)
        // Stop-detection is handled explicitly by pause/resume (T1.2b),
        // not iOS's automatic pausing.
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// Starts a tracking session. `allowsBackgroundLocationUpdates` is
    /// only valid to set to `true` while updates are active and the app
    /// has the `location` UIBackgroundMode (Info.plist) — this is the
    /// mechanism T0.9 validates end-to-end on a physical device.
    func startTracking() {
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isTracking = true
    }

    /// Stops updates entirely (not paused) — per T1.2b's design, a
    /// pause/stop must leave a real time gap with no fabricated
    /// intermediate points, so the anti-cheat teleport check (T2.9)
    /// never has to special-case a pause boundary.
    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isTracking = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        // T0.7 DoD: GPS points visible in console while foregrounded — a
        // plain print, not a logging framework, since this is a
        // throwaway verification aid, not user-facing or persisted.
        print(
            "LocationTrackingService: lat=\(location.coordinate.latitude)" +
                " lng=\(location.coordinate.longitude) alt=\(location.altitude)" +
                " t=\(location.timestamp)"
        )
        locationUpdates.send(location)
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        // Malformed/denied samples are skipped, not fatal — SwiftLint's
        // force_unwrapping=error rule (repo-coding-rules.md §3) exists
        // for exactly this class of failure path.
        print("LocationTrackingService error: \(error.localizedDescription)")
    }
}
