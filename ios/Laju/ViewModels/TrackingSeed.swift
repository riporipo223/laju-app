import Foundation

/// Seed state for `RunViewModel.beginTracking(on:seed:)` — `.empty` for
/// a brand new run (`start()`), populated from a recovered `Run`'s last
/// persisted state for `resumeRecoveredRun(_:)` (T1.14). A plain data
/// struct, extracted to its own file purely to keep `RunViewModel.swift`
/// under SwiftLint's file-length limit (same reasoning as `SplitTracker`).
struct TrackingSeed {
    let route: [GPSPoint]
    let distanceMeters: Double
    let duration: TimeInterval

    static let empty = TrackingSeed(route: [], distanceMeters: 0, duration: 0)
}
