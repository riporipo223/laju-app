import CoreLocation

/// Publishes `CLAuthorizationStatus` and nothing else — the gate behind the Leaderboard tab
/// (product-spec.md §4.5 AC5, added 2026-09-22 when region collection was removed).
///
/// Deliberately NOT `LocationTrackingService`: that type owns a tracking session (start/stop updates,
/// the accuracy/staleness/jitter filters, background-updates toggling). The leaderboard needs one
/// boolean-ish fact — "has the user granted location permission" — and must never start tracking or
/// consume GPS to answer it. This manager never calls `startUpdatingLocation`.
///
/// **Known limitation (CQ-9, code-quality-audit.md):** `RunTrackingView` and `OnboardingContainerView`
/// each already own their own `LocationTrackingService`, and this adds a third `CLLocationManager` to
/// the process. All of them read the same OS-level authorization state, so they cannot disagree — but
/// the proper fix is one shared, injected instance, which is CQ-9's own scope, not this task's.
@MainActor
final class LocationAuthorizationObserver: NSObject, ObservableObject {
    @Published private(set) var status: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    /// Only meaningful while `status == .notDetermined` — iOS silently ignores a second prompt once the
    /// user has answered, which is exactly why `.denied` gets a Settings link instead of this.
    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
}

extension LocationAuthorizationObserver: CLLocationManagerDelegate {
    /// The delegate-supplied parameter is intentionally unused: it is non-Sendable and task-isolated, so
    /// reading it inside the MainActor closure below is a Swift 6 data-race error ("sending 'manager'
    /// risks causing data races"). `self.manager` is the same object but already MainActor-isolated as a
    /// stored property, so read that instead.
    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        // Re-published live: a user can revoke permission in Settings and come back to a still-open
        // Leaderboard tab, and the gate has to close behind them.
        MainActor.assumeIsolated {
            status = self.manager.authorizationStatus
        }
    }
}

/// How the Leaderboard tab should present itself for a given authorization status.
///
/// **The three-way split is an implementation decision that product-spec.md §4.5 AC5 does not specify** —
/// AC5 only describes "granted" vs "denied/not granted". Flagged for confirmation:
/// - `.notDetermined` gets an *ask* CTA rather than the locked/Settings state, because the user has not
///   actually refused anything yet and a Settings deep-link would be confusing.
/// - `.restricted` gets its own copy with NO Settings CTA, because parental controls/MDM mean the user
///   cannot grant it — sending them to Settings is a dead end.
enum LeaderboardAccessState: Equatable {
    case unlocked
    case needsPermission
    case denied
    case restricted

    static func state(for status: CLAuthorizationStatus) -> LeaderboardAccessState {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .unlocked
        case .notDetermined: .needsPermission
        case .restricted: .restricted
        default: .denied
        }
    }
}
