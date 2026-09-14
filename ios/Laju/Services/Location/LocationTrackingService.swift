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
    /// `RunViewModel` (T0.8) to append points to the active `Run`. Only
    /// points that pass the filters below (accuracy/staleness/speed) are
    /// emitted — `RunViewModel` can trust everything it receives here.
    let locationUpdates = PassthroughSubject<CLLocation, Never>()

    private let manager = CLLocationManager()
    private var lastAcceptedLocation: CLLocation?

    /// Reject fixes worse than this. 20m is generous relative to modern
    /// GPS's typical settled accuracy (single-digit meters outdoors) —
    /// wide enough to not choke on ordinary urban-canyon degradation, but
    /// tight enough to reject the cold-fix/multipath readings (tens to
    /// hundreds of meters) that caused the 6459 km/h jump found in
    /// on-device testing (2026-09-10, run pk=34).
    private let maxHorizontalAccuracy: CLLocationAccuracy = 20

    /// Reject a fix whose timestamp is this far from now — a cached/stale
    /// fix reused as if it were live.
    private let maxStalenessSeconds: TimeInterval = 5

    /// Reject a fix implying more than this speed from the last accepted
    /// fix. ~12 m/s (~43 km/h) is a generous sanity ceiling for a human
    /// runner — well above elite sprint pace — chosen deliberately loose
    /// since this is a client-side GPS-jump filter, not the anti-cheat
    /// pace/speed logic already designed server-side in tech-spec.md
    /// §2.4.1 (which operates on different, tighter thresholds against
    /// the full submitted route). The two must not be conflated: this one
    /// only protects local distance/point display from GPS noise.
    private let maxPlausibleSpeedMetersPerSecond: Double = 12

    /// Rejects a step smaller than the reporting accuracy of either
    /// endpoint — added after a real on-device incident (2026-09-11, run
    /// pk=38): a person moved <10m net, but 5 accepted fixes each showed
    /// individually "plausible" walking-speed deltas (11.47m, 14.15m,
    /// 7.96m — none tripped the speed filter above) that were actually
    /// GPS jitter oscillating around one spot (lat drifted south then
    /// back north almost to its starting value), summing to a reported
    /// 33m. No single filter above catches this class of error — it's
    /// not one bad point, it's the accumulation method (sum of
    /// consecutive deltas) having no floor for "was this actually
    /// movement, or just noise within the fix's own uncertainty circle."
    /// Standard GPS-jitter heuristic: don't trust a step you can't
    /// distinguish from the position's own error margin.
    private func isBelowJitterFloor(_ location: CLLocation, comparedTo last: CLLocation) -> Bool {
        let floor = max(location.horizontalAccuracy, last.horizontalAccuracy)
        return location.distance(from: last) < floor
    }

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

    /// Run Tracking Screen (Fase 1 UI): a single fix to center the map on
    /// the user BEFORE Start is tapped (device feedback, 2026-09-13: the
    /// map defaulted to a zoomed-out world view pre-run). `requestLocation()`
    /// delivers through the SAME `didUpdateLocations` delegate callback as
    /// continuous tracking — same accuracy/staleness filtering, same
    /// `lastLocation` published property — so this is one line of reuse,
    /// not a second location pipeline. Independent of `isTracking`/
    /// `startTracking()`/`stopTracking()`: doesn't enable background
    /// updates and stops itself after one fix (or a timeout error).
    func requestOneTimeLocation() {
        manager.requestLocation()
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

    /// Clears filter state left over from a PREVIOUS run — found
    /// necessary on-device (2026-09-13): starting a new run shortly after
    /// a prior one, without moving in between, had every fix in the new
    /// run rejected by the jitter floor against the old run's last
    /// accepted position (same spot, so every step reads as noise) — the
    /// map's `currentCoordinate` never got its first fix, staying
    /// zoomed-out indefinitely. Call this only from a genuinely NEW run's
    /// Start — **never** from `resume()` (T1.2b), which deliberately
    /// keeps filter continuity across a pause within the SAME run.
    func resetSessionFilterState() {
        lastAcceptedLocation = nil
        lastLocation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        if let reason = rejectionReason(for: location) {
            // Rejected points are logged too (T0.7 console requirement
            // extends here) — needed to debug the filter itself, not just
            // the points it lets through.
            print(
                "LocationTrackingService: REJECTED (\(reason)) lat=\(location.coordinate.latitude)" +
                    " lng=\(location.coordinate.longitude) accuracy=\(location.horizontalAccuracy)m" +
                    " t=\(location.timestamp)"
            )
            return
        }

        lastLocation = location
        lastAcceptedLocation = location
        print(
            "LocationTrackingService: lat=\(location.coordinate.latitude)" +
                " lng=\(location.coordinate.longitude) alt=\(location.altitude)" +
                " accuracy=\(location.horizontalAccuracy)m t=\(location.timestamp)"
        )
        locationUpdates.send(location)
    }

    /// `nil` means the point passes all three filters. Order is
    /// accuracy → staleness → speed, checked independently — a point can
    /// fail more than one, but only the first failing reason is reported
    /// (good enough for debugging; the goal is knowing a point was
    /// dropped and roughly why, not full multi-cause diagnostics).
    private func rejectionReason(for location: CLLocation) -> String? {
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > maxHorizontalAccuracy {
            return "accuracy=\(location.horizontalAccuracy)m exceeds \(maxHorizontalAccuracy)m threshold"
        }

        let staleness = abs(location.timestamp.timeIntervalSinceNow)
        if staleness > maxStalenessSeconds {
            return "stale, \(staleness)s old (threshold \(maxStalenessSeconds)s)"
        }

        if let last = lastAcceptedLocation {
            let dt = location.timestamp.timeIntervalSince(last.timestamp)
            if dt > 0 {
                let impliedSpeed = location.distance(from: last) / dt
                if impliedSpeed > maxPlausibleSpeedMetersPerSecond {
                    return "implausible speed \(impliedSpeed)m/s exceeds " +
                        "\(maxPlausibleSpeedMetersPerSecond)m/s threshold"
                }
            }

            if isBelowJitterFloor(location, comparedTo: last) {
                let floor = max(location.horizontalAccuracy, last.horizontalAccuracy)
                let dist = location.distance(from: last)
                return "jitter: step \(dist)m below accuracy floor \(floor)m"
            }
        }

        return nil
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        // Malformed/denied samples are skipped, not fatal — SwiftLint's
        // force_unwrapping=error rule (repo-coding-rules.md §3) exists
        // for exactly this class of failure path.
        print("LocationTrackingService error: \(error.localizedDescription)")
    }
}
