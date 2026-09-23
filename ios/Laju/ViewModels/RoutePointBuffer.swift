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

    /// Merges pending points into `run.gpsRoute`, clearing the buffer only once the merged route is safely
    /// persisted. No-op (`.success`) if nothing is pending.
    ///
    /// CQ-2 fix (code-quality-audit.md): the previous implementation had two silent-total-loss paths — decoding
    /// unreadable existing bytes as `[]` via `?? []` (which silently truncated the route down to just the
    /// pending points) and `try?` on encode (which nil'd out the route entirely on a throw, with `pending`
    /// cleared on the very next line — both copies gone). Neither path logged anything or was distinguishable
    /// from success.
    ///
    /// Fixed by never overwriting a previously-persisted route with less data than it already had: an existing
    /// route that fails to decode, or a merged route that fails to encode, now aborts the flush loudly
    /// (always `print`ed, so it's visible in both debug and release consoles) instead of silently discarding
    /// data, and `pending` is only cleared once the merge has actually been written to `run.gpsRoute`.
    /// Deliberately NOT `assertionFailure`/`fatalError`: a corrupted route or an unencodable point is exactly
    /// the scenario this fix exists to survive — crashing on it would turn a data-loss bug into an app-crash
    /// bug mid-run, which is worse. The caller doesn't have to inspect the result — the two production call
    /// sites (`RunViewModel.stop()`/`periodicFlush()`) just want durability and a failure is already logged
    /// here — but tests use it to assert the failure paths genuinely refuse to destroy data.
    @discardableResult
    func flush(into run: Run) -> RouteFlushResult {
        guard !pending.isEmpty else { return .success }

        let existing: [GPSPoint]
        switch GPSPoint.decodeRouteStrict(from: run.gpsRoute) {
        case .noRoute:
            existing = []
        case let .decoded(points):
            existing = points
        case .corrupted:
            print(
                "RoutePointBuffer.flush: existing gpsRoute for run \(run.id?.uuidString ?? "?") could not be " +
                    "decoded — refusing to overwrite it; \(pending.count) pending point(s) kept for retry"
            )
            return .failure(.corruptedExistingRoute)
        }

        let merged = existing + pending
        do {
            run.gpsRoute = try JSONEncoder().encode(merged)
            pending.removeAll()
            return .success
        } catch {
            print(
                "RoutePointBuffer.flush: failed to encode route for run \(run.id?.uuidString ?? "?") " +
                    "— keeping the previously-persisted gpsRoute untouched; \(pending.count) pending point(s) " +
                    "kept for retry: \(error)"
            )
            return .failure(.encodingFailed(error))
        }
    }
}

enum RouteFlushResult: Equatable {
    case success
    case failure(RouteFlushFailure)
}

enum RouteFlushFailure: Equatable {
    case corruptedExistingRoute
    case encodingFailed(Error)

    static func == (lhs: RouteFlushFailure, rhs: RouteFlushFailure) -> Bool {
        switch (lhs, rhs) {
        case (.corruptedExistingRoute, .corruptedExistingRoute):
            true
        case (.encodingFailed, .encodingFailed):
            true
        default:
            false
        }
    }
}
