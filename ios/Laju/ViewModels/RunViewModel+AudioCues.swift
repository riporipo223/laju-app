import Foundation

/// `RunViewModel`'s T1.13 audio-cue trigger — extracted purely to keep `RunViewModel.swift` under SwiftLint's
/// `type_body_length` limit; behavior identical to being inline.
extension RunViewModel {
    /// Reuses `SplitTracker`'s existing exactly-once-per-km boundary detection (T1.10) as the announcement
    /// trigger, rather than a new detector — `splits.count` only grows when accumulated distance since the
    /// last boundary clears 1000m, so this is already immune to GPS jitter double-firing (product-spec §4.13
    /// AC3), for the same reason splits themselves don't duplicate.
    func announceKmBoundaryIfCrossed(totalActiveDuration: TimeInterval) {
        let splitCountBefore = splitTracker.splits.count
        splitTracker.recordDistanceUpdate(totalDistanceMeters: distanceMeters, totalActiveDuration: totalActiveDuration)
        guard splitTracker.splits.count > splitCountBefore, let newSplit = splitTracker.splits.last else { return }
        audioCueService.announce(kmNumber: newSplit.splitNumber, paceSecPerKm: newSplit.avgPaceSecPerKm)
    }
}
