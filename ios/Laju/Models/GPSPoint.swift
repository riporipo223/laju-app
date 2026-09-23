import CoreLocation
import Foundation

/// Per-point GPS sample shape — matches the `gps_route` API contract
/// exactly (database-api-spec.md §1/§2.2, tech-spec.md §2.1): `timestamp`
/// and `elevation` are required per point, not just lat/lng, since
/// anti-cheat (T2.7–T2.10) needs them for per-segment speed/elevation
/// checks. This struct is encoded into `Run.gpsRoute` (Binary attribute).
struct GPSPoint: Codable {
    let lat: Double
    let lng: Double
    let timestamp: Date
    let elevation: Double

    /// T1.9: shared decode path for the View layer (`RunSummaryView`'s
    /// static map, `RunHistoryView`'s route thumbnails) — mirrors
    /// `RunViewModel`'s own private decode of `Run.gpsRoute`, exposed
    /// here so views don't need their own copy of the same logic.
    static func decodeRoute(from data: Data?) -> [GPSPoint] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([GPSPoint].self, from: data)) ?? []
    }

    /// CQ-2 fix (code-quality-audit.md): `decodeRoute` above collapses "no route yet" and "route bytes exist
    /// but can't be decoded" into the same `[]` — fine for read-only display paths (`RunHistoryView`,
    /// `RunRecovery`), wrong for `RoutePointBuffer.flush`, which must not silently treat undecodable data as
    /// empty and overwrite it. This variant keeps those two cases distinct so a write path can refuse to
    /// destroy data it couldn't read.
    static func decodeRouteStrict(from data: Data?) -> RouteDecodeResult {
        guard let data else { return .noRoute }
        guard let points = try? JSONDecoder().decode([GPSPoint].self, from: data) else { return .corrupted }
        return .decoded(points)
    }

    /// T1.14: reconstructs a `CLLocation` from a persisted point — used by `RunViewModel`'s resume path to
    /// seed the stationary anchor. `horizontalAccuracy`/`verticalAccuracy` are 0 (not persisted per-point) —
    /// harmless, since anchor distance math only reads coordinates, never accuracy.
    func asCLLocation() -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            altitude: elevation,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            timestamp: timestamp
        )
    }
}

/// Result of `GPSPoint.decodeRouteStrict` — distinguishes "no route persisted yet" (`Run.gpsRoute == nil`) from
/// "route bytes exist but could not be decoded" (corruption), which a plain `[GPSPoint]` return can't express.
enum RouteDecodeResult {
    case noRoute
    case decoded([GPSPoint])
    case corrupted
}
