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
}
