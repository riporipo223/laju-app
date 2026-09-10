import Combine
import CoreData
import CoreLocation
import Foundation

/// Ties `LocationTrackingService` (T0.7) to Core Data (T0.6) — MVVM
/// State layer (architecture.md §3). Per the Round 6 audit fix (B6-3):
/// the `Run` object is created and saved at Start, and GPS points are
/// saved incrementally while active, not only once at Stop — otherwise
/// an OS force-kill mid-run would leave no row to recover at all, which
/// is exactly what T0.9's force-kill DoD item tests.
///
/// The incremental save has two independent triggers: every
/// `saveEveryNPoints` points, AND every `flushIntervalSeconds` of wall
/// time. Count-only was the original design, but the T0.9 physical-device
/// force-kill test caught a real gap it left open: a low-activity session
/// (e.g. phone mostly stationary — `distanceFilter` throttles updates, so
/// few points arrive) can run for many minutes without ever reaching the
/// count threshold, leaving nothing flushed to Core Data to survive a
/// kill. The time-based timer is the backstop for exactly that case.
final class RunViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var pointCount = 0
    @Published private(set) var distanceMeters: Double = 0

    private let locationService: LocationTrackingService
    private let context: NSManagedObjectContext
    private var activeRun: Run?
    private var pendingPoints: [GPSPoint] = []
    private var lastLocation: CLLocation?
    private var cancellables = Set<AnyCancellable>()
    private var flushTimerCancellable: AnyCancellable?

    /// Count-based trigger — every N points. 20 points at a typical
    /// few-second GPS interval is roughly a minute of coverage lost at
    /// worst on a force-kill, well within T0.9's tolerance.
    private let saveEveryNPoints = 20

    /// Time-based trigger — backstop for low-activity sessions where the
    /// count threshold may never be reached (see class doc). 30s caps
    /// worst-case data loss on a kill to half a minute regardless of how
    /// many/few points arrived in that window.
    private let flushIntervalSeconds: TimeInterval = 30

    init(locationService: LocationTrackingService, context: NSManagedObjectContext) {
        self.locationService = locationService
        self.context = context

        locationService.locationUpdates
            .sink { [weak self] location in
                self?.handle(location)
            }
            .store(in: &cancellables)
    }

    func start() {
        let run = Run(context: context)
        run.id = UUID()
        run.startedAt = Date()
        run.distanceMeters = 0
        run.durationSeconds = 0
        run.estimatedPoints = 0
        run.syncStatus = "pendingSync"
        try? context.save() // saved immediately at Start — see class doc

        activeRun = run
        pendingPoints = []
        lastLocation = nil
        pointCount = 0
        distanceMeters = 0
        isRunning = true
        locationService.startTracking()

        // Combine timer, not Timer.scheduledTimer — the latter's closure
        // is @Sendable, and weak-capturing a non-Sendable class (this one)
        // in it fails under Swift 6 strict concurrency. Combine's .sink
        // closure runs in the same isolation context as the subscribing
        // code (main, here), matching the existing locationUpdates.sink
        // pattern above.
        flushTimerCancellable = Timer.publish(every: flushIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.periodicFlush()
            }
    }

    func stop() {
        guard let run = activeRun else { return }
        flushTimerCancellable?.cancel()
        flushTimerCancellable = nil
        flushPendingPoints(to: run)
        let endedAt = Date()
        run.endedAt = endedAt
        if let startedAt = run.startedAt {
            run.durationSeconds = endedAt.timeIntervalSince(startedAt)
        }
        try? context.save()

        locationService.stopTracking()
        isRunning = false
        activeRun = nil
    }

    /// Timer-driven flush — the time-based backstop described in the
    /// class doc. A no-op when there's nothing new since the last flush,
    /// so it doesn't force an empty Core Data save every 30s.
    private func periodicFlush() {
        guard let run = activeRun, !pendingPoints.isEmpty else { return }
        flushPendingPoints(to: run)
        try? context.save()
    }

    private func handle(_ location: CLLocation) {
        guard let run = activeRun else { return }

        if let last = lastLocation {
            distanceMeters += location.distance(from: last)
            run.distanceMeters = distanceMeters
        }
        lastLocation = location

        let point = GPSPoint(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            timestamp: location.timestamp,
            elevation: location.altitude
        )
        pendingPoints.append(point)
        pointCount += 1

        if pendingPoints.count >= saveEveryNPoints {
            flushPendingPoints(to: run)
            try? context.save()
        }
    }

    private func flushPendingPoints(to run: Run) {
        guard !pendingPoints.isEmpty else { return }
        var existing = decodeRoute(run.gpsRoute)
        existing.append(contentsOf: pendingPoints)
        run.gpsRoute = try? JSONEncoder().encode(existing)
        pendingPoints.removeAll()
    }

    private func decodeRoute(_ data: Data?) -> [GPSPoint] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([GPSPoint].self, from: data)) ?? []
    }
}
