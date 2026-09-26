import Combine
import CoreData
import CoreLocation
import Foundation

/// Ties `LocationTrackingService` (T0.7) to Core Data (T0.6) — MVVM State layer (architecture.md §3). `Run` is
/// created/saved at Start, GPS points save incrementally (`saveEveryNPoints`/`flushIntervalSeconds`, B6-3) —
/// otherwise a force-kill mid-run leaves no row to recover. T1.14 also uses this timer for `durationSeconds`.
final class RunViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var pointCount = 0
    @Published private(set) var distanceMeters: Double = 0
    /// T4.22 (product-spec.md §4.29): advisory only (ADR-0008) — drives `RunTrackingView`'s warning
    /// banner. Never affects points/penalties itself; the server independently re-derives the real
    /// outcome from `gps_route` on sync.
    @Published private(set) var showsSpeedViolationWarning = false

    /// T1.8: live map state — fed from the same point-append path as `gpsRoute` (`appendPoint(_:to:)`), not a
    /// new `CLLocationManager` subscription. Drives a custom annotation, never `showsUserLocation` (B7-8).
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D] = []

    /// Map heading cone (Fase 1 UI) — reuses `CLLocation.course` from the same object flowing through
    /// `appendPoint(_:to:)`, no new subscription. `nil` when the fix has no valid course.
    @Published private(set) var currentCourseDegrees: CLLocationDirection?

    /// T1.10: per-km splits — see `SplitTracker`. Computed live (fed the same distance/duration this class
    /// already tracks), not re-derived from `gpsRoute` — that would need per-point `horizontalAccuracy`,
    /// which isn't persisted (tech-spec.md §2.1b).
    let splitTracker = SplitTracker()

    /// Live estimate while active (T1.2b) — freezes while paused (same early-return as `distanceMeters`).
    @Published private(set) var currentEstimatedPoints: Double = 0
    /// Set at end of `stop()` — presented as a sheet (T1.2, within 2s).
    @Published var completedRunSummary: RunSummary?

    private let locationService: LocationTrackingService
    private let context: NSManagedObjectContext
    private var activeRun: Run?
    private let routeBuffer = RoutePointBuffer()
    private var lastLocation: CLLocation?
    private var cancellables = Set<AnyCancellable>()
    private var flushTimerCancellable: AnyCancellable?

    /// CQ-11 fix: confirmed-movement increments only (the same ones that feed `distanceMeters`),
    /// kept for `RollingSpeedCalculator` — completely separate from `distanceMeters`/`avg_pace_sec_per_km`,
    /// which are untouched by this fix and stay the authoritative totals for points/history.
    /// Trimmed generously (2x the calculator's own window) on every append so this never grows
    /// unbounded across a multi-hour run — the calculator itself re-filters to the exact window at
    /// read time, this is just a memory bound.
    private var recentMovementSamples: [RollingSpeedCalculator.MovementSample] = []

    /// T4.22: fed alongside `recentMovementSamples` in the same confirmed-movement branch of
    /// `handle(_:)` — same source data, different question asked of it.
    private let severeSpeedViolationDetector = SevereSpeedViolationDetector()

    /// T1.2b: `durationSeconds` excludes paused time — completed segments (`accumulatedActiveDuration`) plus
    /// time since the current one began (`currentSegmentStartedAt`), set at Start/Resume, cleared at Pause/Stop.
    private var accumulatedActiveDuration: TimeInterval = 0
    private var currentSegmentStartedAt: Date?

    /// T1.4: consecutive qualifying days ending YESTERDAY, computed at `start()`/resume, reused by the live
    /// estimate and `stop()`. `effectiveStreakDays` below adds 1 for today only once distance clears
    /// `minDistanceKmForPoints` (tech-spec.md §2.2 grinding-exploit fix).
    var priorStreakDays = 0

    /// Drift guard (run pk=41): stationary indoors ~90min still accumulated 34.9m, none tripping speed/jitter
    /// filters. Fixes the reference at the last CONFIRMED movement.
    private var stationaryAnchor: CLLocation?

    /// A point within this radius of `stationaryAnchor` doesn't count as movement — indoor GPS drift observed in
    /// testing reached 14.32m per step. Larger than the per-step jitter floor because it catches accumulated
    /// multi-step drift, not just one point's own uncertainty.
    private let stationaryRadiusMeters: Double = 20

    /// A fix worse than this can't establish/move `stationaryAnchor` (2026-09-12): a poor first fix
    /// (`accuracy=15.11m`) became the anchor unconditionally; a much-better fix 12s later landed 35m away,
    /// read as real movement though the phone never moved. `static` (not just `private`) so `RunTrackingView`'s
    /// GPS-status banner can read the SAME number instead of a second hardcoded "10" (found in the 2026-09-15
    /// false-trigger review: the two had silently drifted into two separate literals for one concept).
    static let anchorAccuracyThresholdMeters: CLLocationAccuracy = 10

    /// Count-based trigger — 20 points at a typical few-second GPS interval is ~1min of coverage lost at worst.
    private let saveEveryNPoints = 20

    /// Time-based trigger — backstop for low-activity sessions (see class doc). Caps worst-case duration loss on
    /// a kill to one interval. Was 30s, tightened to 5s (2026-09-13, on-device T1.14 testing — mechanism itself
    /// confirmed working via console+DB, the window was just too wide). Not shrunk further: each tick is a
    /// disk-writing `context.save()`. A kill within one interval of a resume still loses that segment (its own
    /// timer restarts from 0) — disclosed limitation. Injectable so tests can verify the REAL timer.
    private let flushIntervalSeconds: TimeInterval
    /// T1.13 — injectable so tests can assert on a spy instead of driving real `AVSpeechSynthesizer` output.
    let audioCueService: AudioCueAnnouncing
    /// T1.16 — injectable so tests don't touch real `UNUserNotificationCenter` state.
    private let streakReminderScheduler: StreakReminderScheduler

    init(
        locationService: LocationTrackingService,
        context: NSManagedObjectContext,
        flushIntervalSeconds: TimeInterval = 5,
        audioCueService: AudioCueAnnouncing = AudioCueService(),
        streakReminderScheduler: StreakReminderScheduler = StreakReminderScheduler()
    ) {
        self.locationService = locationService
        self.context = context
        self.flushIntervalSeconds = flushIntervalSeconds
        self.audioCueService = audioCueService
        self.streakReminderScheduler = streakReminderScheduler

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
        beginTracking(on: run, seed: .empty)
    }

    /// T1.14: reattaches to a `Run` left with no `endedAt`, seeded from its last persisted state, not zero.
    func resumeRecoveredRun(_ run: Run) {
        let route = GPSPoint.decodeRoute(from: run.gpsRoute)
        let seed = TrackingSeed(route: route, distanceMeters: run.distanceMeters, duration: run.durationSeconds)
        beginTracking(on: run, seed: seed)
    }

    /// Shared by `start()`/`resumeRecoveredRun(_:)` — extracted 2026-09-13 (T1.14).
    private func beginTracking(on run: Run, seed: TrackingSeed) {
        activeRun = run
        routeBuffer.clear()
        pointCount = seed.route.count
        distanceMeters = seed.distanceMeters
        recentMovementSamples = []
        severeSpeedViolationDetector.reset()
        showsSpeedViolationWarning = false
        let coordinates = seed.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        routeCoordinates = coordinates
        currentCoordinate = coordinates.last
        currentCourseDegrees = nil
        // T1.14 (resume): treated like a long `pause()` — pause()/resume() never reset the anchor either, so
        // the next fix goes through the SAME distance-from-anchor pipeline as any other point, no special case.
        let lastKnownLocation = seed.route.last?.asCLLocation()
        stationaryAnchor = lastKnownLocation
        lastLocation = lastKnownLocation
        splitTracker.reset(distanceMeters: seed.distanceMeters, activeDuration: seed.duration)
        accumulatedActiveDuration = seed.duration
        currentSegmentStartedAt = Date()
        let startedAt = run.startedAt ?? Date()
        priorStreakDays = PersistenceController.priorStreakDays(asOf: startedAt, in: context, excluding: run.id)
        updateCurrentEstimatedPoints()
        isRunning = true
        isPaused = false
        locationService.resetSessionFilterState()
        locationService.startTracking()

        // Combine timer, not Timer.scheduledTimer, whose @Sendable
        // closure can't weak-capture this non-Sendable class under
        // Swift 6 strict concurrency.
        flushTimerCancellable = Timer.publish(every: flushIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.periodicFlush()
            }
    }

    /// T1.2b. `CLLocationManager` updates stop here (not "keep receiving but ignore") — the gap to the first
    /// post-resume point is a real time gap with no fabricated points, so T2.9's (Fase 2) teleport check can't
    /// misread it as a spurious jump.
    func pause() {
        guard isRunning, !isPaused else { return }
        finalizeActiveSegment()
        isPaused = true
        locationService.stopTracking()
        if let run = activeRun {
            run.durationSeconds = accumulatedActiveDuration
            try? context.save()
        }
    }

    func resume() {
        guard isRunning, isPaused else { return }
        currentSegmentStartedAt = Date()
        isPaused = false
        locationService.startTracking()
    }

    func stop() {
        guard let run = activeRun else { return }
        flushTimerCancellable?.cancel()
        flushTimerCancellable = nil
        routeBuffer.flush(into: run)
        run.endedAt = Date()
        finalizeActiveSegment()
        run.durationSeconds = accumulatedActiveDuration

        // T1.10: trailing partial split — accumulatedActiveDuration is already FINAL here (folded in above).
        splitTracker.finalizePartialSplit(
            totalDistanceMeters: distanceMeters,
            totalActiveDuration: accumulatedActiveDuration
        )

        // streakDays (T1.4) is priorStreakDays + 1 only if THIS run's own final distance qualifies — a
        // 0-distance run must not extend or cash in a streak bonus (see effectiveStreakDays doc).
        let distanceKm = run.distanceMeters / 1000
        let avgPaceSecPerKm = distanceKm > 0 ? run.durationSeconds / distanceKm : 0
        let streakDays = effectiveStreakDays(distanceKm: distanceKm)
        let estimatedPoints = PointFormula.calculatePoints(
            distanceKm: distanceKm,
            avgPaceSecPerKm: avgPaceSecPerKm,
            streakDays: streakDays
        )

        // T1.3: `run.estimatedPoints` is still 0 here (set at Start), so this total correctly excludes the
        // run being finished — the "before" total to compare against.
        let totalBeforeThisRun = PersistenceController.totalEstimatedPoints(in: context)
        let levelBefore = LevelProgression.currentLevel(totalPoints: totalBeforeThisRun)
        let levelAfter = LevelProgression.currentLevel(totalPoints: totalBeforeThisRun + estimatedPoints)
        let leveledUpTo = levelAfter.level > levelBefore.level ? levelAfter : nil

        run.estimatedPoints = estimatedPoints
        try? context.save()
        // hasRunToday mirrors effectiveStreakDays' own qualifying check.
        let hasRunToday = distanceKm >= PointFormula.minDistanceKmForPoints
        streakReminderScheduler.reschedule(currentStreakDays: streakDays, hasRunToday: hasRunToday)

        // T1.12: gpsRoute already fully flushed above — noise floor (not point-exclusion) handles drift periods.
        let elevation = ElevationTracker.compute(points: GPSPoint.decodeRoute(from: run.gpsRoute))

        locationService.stopTracking()
        isRunning = false
        isPaused = false
        completedRunSummary = RunSummary(
            distanceMeters: run.distanceMeters,
            durationSeconds: run.durationSeconds,
            avgPaceSecPerKm: avgPaceSecPerKm,
            estimatedPoints: estimatedPoints,
            leveledUpTo: leveledUpTo,
            streakDays: streakDays,
            routeCoordinates: routeCoordinates,
            splits: splitTracker.splits,
            elevationGainMeters: elevation.gainMeters,
            elevationLossMeters: elevation.lossMeters
        )
        activeRun = nil

        // The idle tracking screen reads these same @Published properties (RunTrackingView's
        // liveDuration/liveDistanceMeters) — without resetting them here, Time/Distance/Pace stay
        // frozen at the just-finished run's final values until the next Start, instead of showing
        // 0 while idle. completedRunSummary above already captured the final values for
        // RunSummaryView, so these are safe to zero now.
        distanceMeters = 0
        accumulatedActiveDuration = 0
        pointCount = 0
        routeCoordinates = []
        currentCoordinate = nil
        currentCourseDegrees = nil
        currentEstimatedPoints = 0
        recentMovementSamples = []
        severeSpeedViolationDetector.reset()
        showsSpeedViolationWarning = false
    }

    /// T4.21: Save Activity's "Save Activity (Publish)" button — captures `activeRun` before `stop()` clears
    /// it (the `NSManagedObject` reference itself stays valid across that, same context), then writes the
    /// drafted fields and sets `pendingPostRequested`. The actual `POST /api/social/posts` call happens
    /// later, once the run is `validated`/`approved` server-side (`PendingPostPublisher`, wired into
    /// `SyncService`/`ReconciliationService`) — this run may still be `pendingSync` the instant this
    /// function returns.
    func finishAndRequestPost(
        title: String?,
        description: String?,
        privateNotes: String?,
        mapType: String,
        visibility: String,
        gearId: String?
    ) {
        guard let run = activeRun else { return }
        stop()
        run.pendingPostTitle = title
        run.pendingPostDescription = description
        run.pendingPostPrivateNotes = privateNotes
        run.pendingPostMapType = mapType
        run.pendingPostVisibility = visibility
        run.pendingPostGearId = gearId
        run.pendingPostRequested = true
        try? context.save()
    }

    /// Folds time since the current segment began into `accumulatedActiveDuration` — shared by `pause()`/`stop()`,
    /// a no-op if already paused.
    private func finalizeActiveSegment() {
        guard let segmentStart = currentSegmentStartedAt else { return }
        accumulatedActiveDuration += Date().timeIntervalSince(segmentStart)
        currentSegmentStartedAt = nil
    }

    /// Timer-driven flush. Always persists `durationSeconds` (T1.14, §4.14 / Round 7 B7-2/B7-P1) even with no
    /// new points — a crash mid-active-segment that never paused previously left it at 0 forever, making a
    /// resume's elapsed time unrecoverable. Reuses this SAME timer trigger, not a new mechanism.
    private func periodicFlush() {
        guard let run = activeRun else { return }
        routeBuffer.flush(into: run)
        run.durationSeconds = liveActiveDuration()
        try? context.save()
    }

    private func handle(_ location: CLLocation) {
        guard let run = activeRun, !isPaused else { return }

        guard let anchor = stationaryAnchor else {
            // First point — only trust it as the anchor if accurate enough (anchorAccuracyThresholdMeters
            // doc); a poor first fix must not seed a bad reference. Either way the raw point is recorded.
            if location.horizontalAccuracy <= Self.anchorAccuracyThresholdMeters {
                stationaryAnchor = location
                lastLocation = location
                updateCurrentEstimatedPoints()
            }
            appendPoint(location, to: run)
            return
        }

        let distanceFromAnchor = location.distance(from: anchor)
        if distanceFromAnchor <= stationaryRadiusMeters {
            // Within the anchor's noise radius — recorded raw, but does NOT count toward distance and does
            // NOT move the anchor/lastLocation. Keeping the anchor fixed is what stops it drifting (class doc).
            appendPoint(location, to: run)
            return
        }

        guard location.horizontalAccuracy <= Self.anchorAccuracyThresholdMeters else {
            // Beyond the radius, but this fix itself is poor — don't trust it as the new anchor. Wait for a
            // better fix; the raw point is still recorded.
            appendPoint(location, to: run)
            return
        }

        // Beyond the radius and accurate enough — real movement. Count from the last confirmed-movement
        // point, then this point becomes the new anchor.
        let previousPoint = lastLocation ?? anchor
        let confirmedIncrementMeters = location.distance(from: previousPoint)
        distanceMeters += confirmedIncrementMeters
        run.distanceMeters = distanceMeters
        recordMovementSample(confirmedIncrementMeters, at: location.timestamp)
        recordSevereSpeedSample(confirmedIncrementMeters, from: previousPoint.timestamp, to: location.timestamp)
        stationaryAnchor = location
        lastLocation = location
        let activeDuration = liveActiveDuration()
        updateCurrentEstimatedPoints(activeDuration: activeDuration)
        announceKmBoundaryIfCrossed(totalActiveDuration: activeDuration)

        appendPoint(location, to: run)
    }

    /// CQ-11 fix: feeds `RollingSpeedCalculator` — see `recentMovementSamples`'s own doc for why this
    /// is separate from `distanceMeters`.
    private func recordMovementSample(_ distanceMeters: Double, at timestamp: Date) {
        recentMovementSamples.append(RollingSpeedCalculator.MovementSample(timestamp: timestamp, distanceMeters: distanceMeters))
        let staleBefore = Date().addingTimeInterval(-RollingSpeedCalculator.defaultWindowSeconds * 2)
        recentMovementSamples.removeAll { $0.timestamp < staleBefore }
    }

    /// T4.22: feeds `SevereSpeedViolationDetector` with this point's own instantaneous speed —
    /// converted to km/h to share the exact threshold the backend's severe check uses.
    private func recordSevereSpeedSample(_ distanceMeters: Double, from previousTimestamp: Date, to timestamp: Date) {
        let elapsedSeconds = timestamp.timeIntervalSince(previousTimestamp)
        guard elapsedSeconds > 0 else { return }
        let speedKmh = (distanceMeters / elapsedSeconds) * 3.6
        severeSpeedViolationDetector.record(speedKmh: speedKmh, at: timestamp)
        showsSpeedViolationWarning = severeSpeedViolationDetector.isTriggered
    }

    /// CQ-11 fix: the Run Tracking screen's live speed stat, recomputed fresh on every call (its
    /// `TimelineView` already re-renders every second) — `nil` means "not enough recent data," the
    /// view shows a neutral placeholder rather than a stale or wild number.
    func liveRollingPaceSecPerKm() -> Double? {
        RollingSpeedCalculator.rollingPaceSecPerKm(samples: recentMovementSamples, now: Date())
    }

    /// T1.2b: recomputes the live estimate. Only called from `handle(_:)`, which itself early-returns while
    /// paused, so this never runs during a pause — which is what keeps the displayed value frozen.
    ///
    /// `activeDuration` is optional so most call sites can keep computing it internally — but the
    /// confirmed-movement path in `handle(_:)` passes its own already-computed value instead of calling
    /// `liveActiveDuration()` a second time in the same GPS-fix handler (found in review 2026-09-14: two
    /// independent `Date()`-based reads a few lines apart could disagree by the time between them, however
    /// small).
    private func updateCurrentEstimatedPoints(activeDuration: TimeInterval? = nil) {
        let distanceKm = distanceMeters / 1000
        let avgPaceSecPerKm = distanceKm > 0 ? (activeDuration ?? liveActiveDuration()) / distanceKm : 0
        currentEstimatedPoints = PointFormula.calculatePoints(
            distanceKm: distanceKm,
            avgPaceSecPerKm: avgPaceSecPerKm,
            streakDays: effectiveStreakDays(distanceKm: distanceKm)
        )
    }

    /// Active duration so far, including the still-open segment — shared by the live point estimate (T1.2b),
    /// split tracking (T1.10), and the tracking screen's Time stat. `internal` so the view can re-read it.
    func liveActiveDuration() -> TimeInterval {
        accumulatedActiveDuration + (currentSegmentStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func appendPoint(_ location: CLLocation, to run: Run) {
        let coord = location.coordinate
        let point = GPSPoint(
            lat: coord.latitude,
            lng: coord.longitude,
            timestamp: location.timestamp,
            elevation: location.altitude
        )
        routeBuffer.append(point)
        pointCount += 1
        currentCoordinate = location.coordinate
        currentCourseDegrees = location.course >= 0 ? location.course : nil
        routeCoordinates.append(location.coordinate)

        if routeBuffer.count >= saveEveryNPoints {
            routeBuffer.flush(into: run)
            run.durationSeconds = liveActiveDuration() // T1.14 — see periodicFlush()'s doc
            try? context.save()
        }
    }
}
