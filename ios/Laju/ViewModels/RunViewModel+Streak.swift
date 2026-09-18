import Foundation

/// `RunViewModel`'s streak-qualification helper — extracted purely to keep `RunViewModel.swift` under
/// SwiftLint's `type_body_length` limit; behavior identical to being inline.
extension RunViewModel {
    /// Grinding-exploit fix (tech-spec.md §2.2): `priorStreakDays` (qualifying days ending YESTERDAY) only
    /// extends to today once today's distance clears `minDistanceKmForPoints` — a run that never reaches it
    /// neither earns points nor counts as "ran today" for tomorrow's streak.
    func effectiveStreakDays(distanceKm: Double) -> Int {
        distanceKm >= PointFormula.minDistanceKmForPoints ? priorStreakDays + 1 : priorStreakDays
    }
}
