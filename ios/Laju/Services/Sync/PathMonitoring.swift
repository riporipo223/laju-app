import Foundation
import Network

/// T2.14: abstracts connectivity observation so `SyncService`'s "sync automatically once connectivity
/// returns" behavior is testable without toggling real network state (this codebase has no existing
/// NWPathMonitor usage or injection seam to reuse). `onUpdate` fires with `true` when the path is
/// `.satisfied`, `false` otherwise — callers care about the boolean transition, not `NWPath` internals.
protocol PathMonitoring: Sendable {
    func start(onUpdate: @escaping @Sendable (Bool) -> Void)
    func cancel()
}

/// Real implementation, backed by `NWPathMonitor`. `final class` + `@unchecked Sendable` rather than an
/// actor — `NWPathMonitor` already serializes its own callback delivery onto the queue given to
/// `start(queue:)`, so there is no additional shared mutable state here needing actor isolation (same
/// precedent as `StreakReminderScheduler`'s `@unchecked Sendable`, ios/Laju/ViewModels/StreakReminderScheduler.swift).
final class NWPathMonitorAdapter: PathMonitoring, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.laju.pathmonitor")

    func start(onUpdate: @escaping @Sendable (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in
            onUpdate(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}
