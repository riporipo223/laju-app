import Foundation

/// Buffers newly-recorded GPS points before they're merged into `Run.gpsRoute` — extracted out of
/// `RunViewModel` purely to keep its `type_body_length` under SwiftLint's limit; behavior is identical to
/// being inline (same count-based flush trigger in `RunViewModel.appendPoint`).
final class RoutePointBuffer {
    private(set) var pending: [GPSPoint] = []

    var count: Int {
        pending.count
    }

    func append(_ point: GPSPoint) {
        pending.append(point)
    }

    /// T1.14: used when (re)starting tracking on a `Run` — the buffer must not carry over points from a prior
    /// session's leftover state.
    func clear() {
        pending.removeAll()
    }

    /// Merges pending points into `run.gpsRoute`, clearing the buffer. No-op if nothing pending.
    func flush(into run: Run) {
        guard !pending.isEmpty else { return }
        var existing = GPSPoint.decodeRoute(from: run.gpsRoute)
        existing.append(contentsOf: pending)
        run.gpsRoute = try? JSONEncoder().encode(existing)
        pending.removeAll()
    }
}
